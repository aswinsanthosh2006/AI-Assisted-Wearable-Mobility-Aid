# copy_assets.ps1
# Run this script from the project root to copy all assets
# into the docs/images/ directory with clean filenames.
#
# Usage (from the blind/ project root):
#   powershell -ExecutionPolicy Bypass -File scripts/copy_assets.ps1

$images = @(
    @{ Src = "WhatsApp Image 2026-10-29 at 7.17.26 PM.jpeg"; Dst = "docs\images\circuit-design.jpeg" },
    @{ Src = "WhatsApp Image 2026-10-29 at 7.24.09 PM.jpeg"; Dst = "docs\images\cap-concept.jpeg" },
    @{ Src = "Screenshot 2026-10-29 201939.png";              Dst = "docs\images\multi-object-and-phone-detection.png" },
    @{ Src = "Screenshot 2026-10-29 201943.png";              Dst = "docs\images\chair-detection.png" }
)

foreach ($img in $images) {
    if (Test-Path $img.Src) {
        Copy-Item $img.Src $img.Dst -Force
        Write-Host "Copied: $($img.Dst)"
    } else {
        Write-Warning "Source not found: $($img.Src)"
    }
}

Write-Host "`nDone."
