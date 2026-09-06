"""
Disease Classification Training Script
----------------------------------------
Fine-tunes a MobileViT-Small (via timm) on PlantVillage-style
folder-structured data for lightweight, mobile-oriented inference.

Expected dataset layout (PlantVillage default):
    dataset/
        Tomato___Early_blight/
            img001.jpg
            ...
        Tomato___Late_blight/
            ...
        Tomato___healthy/
            ...
        Apple___Black_rot/
            ...

Download PlantVillage via Hugging Face:
    from datasets import load_dataset
    ds = load_dataset("mohanty/PlantVillage", "color")

Install deps:
    pip install torch torchvision timm --break-system-packages

Run:
    python train_mobilevit.py --data_dir ./dataset --epochs 15

DATA AUGMENTATION (mandatory per project spec): the goal is a model
that generalizes to real farmer-captured photos - different angles,
lighting, distances, phone cameras - not just the clean, centered
PlantVillage lab photos it's trained on. Every augmentation below is
mild/conservative on purpose (per spec: "do not use unrealistic
augmentation strengths") - each one simulates a plausible real-world
capture condition, not an artificial distortion.

TRAIN/VAL/TEST SPLIT: this now does a proper 3-way split, not just
train/val. The test set is held out and NEVER touched during training
or model selection (checkpoint saving uses val_acc, not test_acc) -
only evaluated once at the very end, exactly per spec requirement
"keep a final test set that the model has never seen during training."

IMPORTANT BUG THIS FIXES: the previous version of this script created
ONE ImageFolder dataset object, split it into train/val Subsets via
random_split, then set `val_ds.dataset.transform = ...`. Because
random_split's Subsets share the SAME underlying dataset object,
that line silently overwrote the transform for BOTH subsets - meaning
the training set silently lost all its augmentation, undetected. This
version creates separate dataset objects per split (with different
transforms), and uses one shared index split so train/val/test
contain the same images either way.
"""

import argparse
import os
import random
import time

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Subset
from torchvision import datasets, transforms

try:
    import timm
except ImportError as e:
    raise SystemExit(
        "timm is required: pip install timm --break-system-packages"
    ) from e


IMG_SIZE = 224
MEAN = [0.485, 0.456, 0.406]
STD = [0.229, 0.224, 0.225]


def add_gaussian_noise(tensor: torch.Tensor, std: float = 0.02) -> torch.Tensor:
    """Small random noise - simulates phone camera sensor noise in
    low light, one of the explicitly required augmentations. std=0.02
    on a [0,1]-ish normalized tensor is mild by design.
    """
    return tensor + torch.randn_like(tensor) * std


class AddGaussianNoise:
    """Class-based (not a local lambda) so this is picklable - required
    on Windows, where DataLoader worker processes must pickle the
    entire transform pipeline to hand it to worker subprocesses. A
    lambda defined inside a function is NOT picklable and crashes with
    `_pickle.PicklingError: Can't pickle local object` the moment any
    DataLoader worker tries to start (num_workers > 0)."""

    def __init__(self, std: float = 0.02):
        self.std = std

    def __call__(self, tensor: torch.Tensor) -> torch.Tensor:
        return add_gaussian_noise(tensor, self.std)


def build_transforms(train: bool):
    if train:
        return transforms.Compose([
            # Random crop + resize covers both "random crop and resize"
            # AND "zoom in and zoom out" from the spec - scale=(0.8, 1.0)
            # means we never zoom in so far that context is lost, and
            # never zoom out past the original framing.
            transforms.RandomResizedCrop(IMG_SIZE, scale=(0.8, 1.0), ratio=(0.9, 1.1)),
            # Horizontal flip - leaves photographed from either side
            # look equally valid.
            transforms.RandomHorizontalFlip(),
            # Small rotations - camera tilt is common in handheld shots.
            # Spec suggests up to +-30 degrees; kept at the upper end
            # of "mild" rather than larger, unrealistic rotations.
            transforms.RandomRotation(30),
            # Small translation/shift - the leaf isn't always perfectly
            # centered in a farmer's photo.
            transforms.RandomAffine(degrees=0, translate=(0.08, 0.08)),
            # Mild perspective distortion - simulates photographing the
            # leaf at a slight angle rather than perfectly flat-on.
            transforms.RandomPerspective(distortion_scale=0.15, p=0.3),
            # Brightness/contrast/saturation variation - covers both
            # "brightness variation" and "contrast variation" and
            # "slight darker and lighter conditions" from the spec.
            # Conservative ranges (0.2-0.25) per "do not use unrealistic
            # augmentation strengths".
            transforms.ColorJitter(brightness=0.25, contrast=0.25, saturation=0.2, hue=0.02),
            # Mild blur, applied only sometimes - simulates a
            # slightly-out-of-focus phone photo, not a badly blurry one
            # (badly blurry photos should be caught by the separate
            # Image Quality Gate, not learned as "normal" by this model).
            transforms.RandomApply([transforms.GaussianBlur(kernel_size=3, sigma=(0.1, 1.0))], p=0.2),
            transforms.ToTensor(),
            transforms.Normalize(MEAN, STD),
            # Small sensor-noise simulation - applied last, after
            # normalization, as a small perturbation on the final tensor.
            AddGaussianNoise(std=0.02),
        ])
    # Validation/test transforms are intentionally NOT augmented - they
    # need to reflect real, unmodified images so the reported accuracy
    # means what it says.
    return transforms.Compose([
        transforms.Resize((IMG_SIZE, IMG_SIZE)),
        transforms.ToTensor(),
        transforms.Normalize(MEAN, STD),
    ])


def build_model(num_classes: int):
    # mobilevit_s = MobileViT-Small, pretrained on ImageNet
    model = timm.create_model("mobilevit_s", pretrained=True, num_classes=num_classes)
    return model


def split_indices(n: int, val_fraction: float, test_fraction: float, seed: int = 42):
    """One shared, seeded index split reused across all three dataset
    objects below - this is what guarantees train/val/test never
    overlap even though each split is a separate ImageFolder instance
    with its own transform.
    """
    indices = list(range(n))
    random.Random(seed).shuffle(indices)
    val_size = int(n * val_fraction)
    test_size = int(n * test_fraction)
    val_idx = indices[:val_size]
    test_idx = indices[val_size:val_size + test_size]
    train_idx = indices[val_size + test_size:]
    return train_idx, val_idx, test_idx


def evaluate(model, loader, device):
    model.eval()
    correct, total = 0, 0
    with torch.no_grad():
        for images, labels in loader:
            images, labels = images.to(device), labels.to(device)
            outputs = model(images)
            _, predicted = torch.max(outputs, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()
    return correct / total if total else 0.0


def train(args):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")

    # Two separate ImageFolder objects over the SAME directory, each
    # with its own transform - this is the fix for the shared-transform
    # bug described in the module docstring above. A third one is
    # created for the held-out test split, also with clean transforms.
    train_dataset_full = datasets.ImageFolder(args.data_dir, transform=build_transforms(train=True))
    eval_dataset_full = datasets.ImageFolder(args.data_dir, transform=build_transforms(train=False))
    class_names = train_dataset_full.classes
    print(f"Found {len(class_names)} classes: {class_names}")

    train_idx, val_idx, test_idx = split_indices(
        len(train_dataset_full), args.val_split, args.test_split
    )
    print(f"Split sizes - train: {len(train_idx)}, val: {len(val_idx)}, test: {len(test_idx)}")

    train_ds = Subset(train_dataset_full, train_idx)
    val_ds = Subset(eval_dataset_full, val_idx)
    test_ds = Subset(eval_dataset_full, test_idx)

    # num_workers=0 (main process only) - deliberately not using
    # multiprocessing workers here. Windows DataLoader workers require
    # pickling the entire dataset+transform pipeline to hand off to
    # worker subprocesses, which is a recurring source of fragile,
    # hard-to-debug crashes on Windows specifically (as opposed to
    # Linux/Mac). Single-process loading is slightly slower but far
    # more robust - worth the tradeoff given training already runs for
    # hours; an extra robustness margin matters more than the modest
    # loading-speed gain here.
    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True, num_workers=0)
    val_loader = DataLoader(val_ds, batch_size=args.batch_size, shuffle=False, num_workers=0)
    test_loader = DataLoader(test_ds, batch_size=args.batch_size, shuffle=False, num_workers=0)

    model = build_model(len(class_names)).to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)

    # Sanity check: snapshot one BatchNorm weight BEFORE any training,
    # then compare it after the very first optimizer.step() below. If
    # it hasn't moved from its default-initialized value (1.0), that's
    # an immediate, few-seconds signal that gradients aren't reaching
    # the model's parameters at all - catching this bug in seconds
    # rather than after hours of training that quietly did nothing.
    _sanity_param_name = "stem.bn.weight"
    _sanity_before = model.state_dict()[_sanity_param_name].clone()
    _sanity_checked = False

    best_acc = 0.0
    for epoch in range(args.epochs):
        model.train()
        start = time.time()
        running_loss = 0.0
        for batch_idx, (images, labels) in enumerate(train_loader):
            images, labels = images.to(device), labels.to(device)
            optimizer.zero_grad()
            outputs = model(images)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            running_loss += loss.item() * images.size(0)

            if not _sanity_checked:
                _sanity_checked = True
                _after = model.state_dict()[_sanity_param_name]
                moved = not torch.equal(_sanity_before, _after)
                print(
                    f"\nSANITY CHECK after first optimizer step: "
                    f"'{_sanity_param_name}' changed = {moved}"
                )
                if not moved:
                    print(
                        "WARNING: weights did NOT change after the first training "
                        "step. Training is not actually updating the model - stop "
                        "now (Ctrl+C) rather than waiting hours for a broken run. "
                        "Check that loss.backward() and optimizer.step() are being "
                        "reached, and that model.parameters() (not a frozen copy) "
                        "was passed to the optimizer.\n"
                    )
                print()

            # Print progress every 20 batches - lets you WATCH loss
            # actually decrease during training, rather than waiting
            # hours to find out only at the end whether learning
            # happened at all. A loss that stays flat/doesn't decrease
            # from batch to batch is an early warning sign, not
            # something to only discover after the full epoch.
            if batch_idx % 20 == 0:
                print(
                    f"  epoch {epoch+1}, batch {batch_idx}/{len(train_loader)} "
                    f"| batch_loss={loss.item():.4f}"
                )

        scheduler.step()
        train_loss = running_loss / len(train_ds)

        # Model selection uses VALIDATION accuracy only - the test set
        # is never looked at until the very end, per spec.
        val_acc = evaluate(model, val_loader, device)

        print(
            f"Epoch {epoch+1}/{args.epochs} | "
            f"train_loss={train_loss:.4f} | val_acc={val_acc:.4f} | "
            f"time={time.time()-start:.1f}s"
        )

        if val_acc > best_acc:
            best_acc = val_acc
            os.makedirs(args.output_dir, exist_ok=True)
            torch.save(
                {"model_state": model.state_dict(), "class_names": class_names},
                os.path.join(args.output_dir, "mobilevit_best.pt"),
            )
            print(f"  -> saved new best checkpoint (val_acc={val_acc:.4f})")

    print(f"Training complete. Best val_acc={best_acc:.4f}")

    # Final, one-time evaluation on the held-out test set - this is the
    # number to report/document, since it's the only one the model
    # never influenced its own training or checkpoint-selection with.
    print("Loading best checkpoint for final test-set evaluation...")
    best_checkpoint = torch.load(
        os.path.join(args.output_dir, "mobilevit_best.pt"), map_location=device, weights_only=False
    )
    model.load_state_dict(best_checkpoint["model_state"])
    test_acc = evaluate(model, test_loader, device)
    print(f"FINAL TEST SET ACCURACY (never seen during training): {test_acc:.4f}")
    print("Report this number, not val_acc, as the model's real-world accuracy estimate.")

    print("Next step: run inference_server.py to serve this model over HTTP.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data_dir", type=str, required=True)
    parser.add_argument("--output_dir", type=str, default="./checkpoints")
    parser.add_argument("--epochs", type=int, default=15)
    parser.add_argument("--batch_size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--val_split", type=float, default=0.15)
    parser.add_argument("--test_split", type=float, default=0.15)
    args = parser.parse_args()
    train(args)
