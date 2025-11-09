#!/usr/bin/env bash
# ==========================================================
# Arch Linux Custom Repository Manager + Chroot Builder
# Gyfooya : v1.0                            09 Nov 2025
#
# 1/ Regenerate database with repo-add
# 2/ Remove package from database with repo-remove
# 3/ Build package (AUR/PKGBUILD) in chroot
# 4/ Exit
# ==========================================================

REPO_DIR="/srv/http/REPOSITORY"
PKG_DIR="${REPO_DIR}/x86_64"
CHROOT_DIR="$HOME/chroots/aur-root"

# Ensure required tools are available
for cmd in makechrootpkg mkarchroot repo-add repo-remove git; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Missing required tool: $cmd"
    echo "   Install with: sudo pacman -S --needed devtools base-devel git"
    exit 1
  fi
done

# Auto-detect repo database name
DB_FILE=$(find "$PKG_DIR" -maxdepth 1 -name "*.db.tar.gz" | head -n 1)
if [[ -z "$DB_FILE" ]]; then
  read -rp "Enter your repository name (without .db.tar.gz): " REPO_NAME
  DB_FILE="${PKG_DIR}/${REPO_NAME}.db.tar.gz"
else
  REPO_NAME=$(basename "$DB_FILE" .db.tar.gz)
fi

# Ensure package directory exists
sudo mkdir -p "$PKG_DIR"

echo "=== Arch Linux Repository Manager ==="
echo "Repository path: $REPO_DIR"
echo "Packages path  : $PKG_DIR"
echo "Database file  : $DB_FILE"
echo "Chroot dir     : $CHROOT_DIR/root"
echo
echo "Choose an action:"
echo "  1) Regenerate database with repo-add"
echo "  2) Remove package from database with repo-remove"
echo "  3) Build package (AUR/PKGBUILD) in chroot"
echo "  4) Exit"
read -rp "Enter your choice [1-4]: " choice
echo

case "$choice" in
  1)
    echo "Regenerating database..."
    cd "$PKG_DIR" || { echo "Error: Cannot enter $PKG_DIR"; exit 1; }
    sudo rm -f "${PKG_DIR}/${REPO_NAME}.db"* "${PKG_DIR}/${REPO_NAME}.files"*
    sudo repo-add "${PKG_DIR}/${REPO_NAME}.db.tar.gz" ./*.pkg.tar.*
    echo "✅ Database successfully regenerated."
    ;;

  2)
    echo "Packages currently listed in the database:"
    sudo repo-remove -l "$DB_FILE"
    echo
    read -rp "Enter the package name to remove: " pkgname
    if [[ -n "$pkgname" ]]; then
      sudo repo-remove "$DB_FILE" "$pkgname"
      echo "🗑️  Package '$pkgname' removed from database."
    else
      echo "⚠️  No package name entered. Aborting."
    fi
    ;;

  3)
    echo "=== Build package in clean chroot ==="
    read -rp "Enter AUR URL or local PKGBUILD directory: " src
    WORKDIR=$(mktemp -d)

    # Prepare package source
    if [[ "$src" == http* ]]; then
      git clone "$src" "$WORKDIR" || { echo "❌ Error cloning $src"; exit 1; }
    else
      cp -r "$src"/* "$WORKDIR" || { echo "❌ Error copying from $src"; exit 1; }
    fi

    # Ensure chroot exists properly
    if [[ ! -d "$CHROOT_DIR/root" ]]; then
      echo "Creating chroot environment at $CHROOT_DIR/root ..."
      sudo mkdir -p "$CHROOT_DIR"
      sudo mkarchroot "$CHROOT_DIR/root" base-devel
    else
      echo "✅ Chroot environment found at $CHROOT_DIR/root"
    fi

    echo "Building package in chroot..."
    cd "$WORKDIR" || exit 1
    sudo makechrootpkg -c -r "$CHROOT_DIR"
    build_status=$?

    echo
    if [[ $build_status -ne 0 ]]; then
      echo "❌ Build failed inside chroot."
      rm -rf "$WORKDIR"
      exit 1
    fi

    echo "Copying built package(s) to repository..."
    pkg_files=$(find "$WORKDIR" -maxdepth 1 -type f -name "*.pkg.tar.*")

    if [[ -z "$pkg_files" ]]; then
      echo "❌ No packages were built. Check for build errors above."
    else
      sudo cp $pkg_files "$PKG_DIR"
      echo "Updating repository database..."
      cd "$PKG_DIR" || exit 1
      sudo repo-add "${PKG_DIR}/${REPO_NAME}.db.tar.gz" ./*.pkg.tar.*
      echo "✅ Build complete. Packages added to repository."
    fi

    rm -rf "$WORKDIR"
    ;;

  4)
    echo "Exiting..."
    exit 0
    ;;

  *)
    echo "Invalid choice."
    exit 1
    ;;
esac
