#!/usr/bin/env bash
# =============================================================
# scripts/generate-report.sh
# Generates PDF reports from JaCoCo HTML and Surefire HTML
#
# Usage:  bash scripts/generate-report.sh <BUILD_NUMBER> <GIT_SHORT>
# Place:  scripts/generate-report.sh  (repo root/scripts/)
# Perms:  chmod +x scripts/generate-report.sh
# =============================================================
set -euo pipefail

BUILD_NUM="${1:-0}"
GIT_SHORT="${2:-unknown}"
DATE=$(date +%Y%m%d-%H%M)
OUT_DIR="reports"

echo "============================================"
echo "  PDF Report Generator — spring3hibernate"
echo "  Build #${BUILD_NUM} | Commit: ${GIT_SHORT}"
echo "============================================"

mkdir -p "${OUT_DIR}"

# ── Verify wkhtmltopdf is installed ──────────────────────────
if ! command -v wkhtmltopdf >/dev/null 2>&1; then
    echo ""
    echo "ERROR: wkhtmltopdf is not installed on this Jenkins agent."
    echo ""
    echo "Fix (Ubuntu/Debian):"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y wkhtmltopdf xvfb fonts-liberation"
    echo ""
    echo "Fix (Docker agent — add to Dockerfile):"
    echo "  RUN apt-get update && apt-get install -y wkhtmltopdf xvfb fonts-liberation"
    echo ""
    exit 1
fi

echo "wkhtmltopdf version: $(wkhtmltopdf --version 2>&1 | head -1)"

# ── Shared wkhtmltopdf options ────────────────────────────────
WKHTML_OPTS=(
    "--enable-local-file-access"
    "--page-size"        "A4"
    "--orientation"      "Portrait"
    "--margin-top"       "15mm"
    "--margin-bottom"    "15mm"
    "--margin-left"      "12mm"
    "--margin-right"     "12mm"
    "--footer-center"    "[page] of [topage]"
    "--footer-font-size" "9"
    "--quiet"
)

PDF_COUNT=0

# ── 1. JaCoCo Coverage Report PDF ────────────────────────────
JACOCO_HTML="target/site/jacoco/index.html"
if [ -f "${JACOCO_HTML}" ]; then
    COVERAGE_PDF="${OUT_DIR}/coverage-build${BUILD_NUM}-${GIT_SHORT}-${DATE}.pdf"
    wkhtmltopdf "${WKHTML_OPTS[@]}" \
        --title   "spring3hibernate Coverage Report — Build #${BUILD_NUM}" \
        --header-center "spring3hibernate | JaCoCo Coverage | Build #${BUILD_NUM} | ${GIT_SHORT}" \
        "${JACOCO_HTML}" \
        "${COVERAGE_PDF}"
    echo "Coverage PDF:     ${COVERAGE_PDF}"
    PDF_COUNT=$((PDF_COUNT + 1))
else
    echo "WARNING: ${JACOCO_HTML} not found — skipping coverage PDF"
    echo "         Run 'mvn jacoco:report' before this stage"
fi

# ── 2. Surefire Test Results PDF ──────────────────────────────
SUREFIRE_HTML="target/site/surefire-report.html"
if [ -f "${SUREFIRE_HTML}" ]; then
    SUREFIRE_PDF="${OUT_DIR}/test-results-build${BUILD_NUM}-${DATE}.pdf"
    wkhtmltopdf "${WKHTML_OPTS[@]}" \
        --title   "spring3hibernate Test Results — Build #${BUILD_NUM}" \
        --header-center "spring3hibernate | Test Results | Build #${BUILD_NUM}" \
        "${SUREFIRE_HTML}" \
        "${SUREFIRE_PDF}"
    echo "Test results PDF: ${SUREFIRE_PDF}"
    PDF_COUNT=$((PDF_COUNT + 1))
else
    echo "WARNING: ${SUREFIRE_HTML} not found — skipping test results PDF"
    echo "         Run 'mvn surefire-report:report-only' before this stage"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ${PDF_COUNT} PDF(s) generated in ${OUT_DIR}/"
echo "============================================"
ls -lh "${OUT_DIR}/"*.pdf 2>/dev/null || echo "  (no PDFs found)"
