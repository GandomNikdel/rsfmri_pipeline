#!/bin/bash

set -euo pipefail

BASE=~/wrkdir/HBNFINAL
cd "$BASE"

LOGDIR="$BASE/logs"
mkdir -p "$LOGDIR"

MASTERLOG="$LOGDIR/mcflirt_v2_master.log"

echo "====================================" >> "$MASTERLOG"
echo "MCFLIRT V2 START: $(date)" >> "$MASTERLOG"
echo "HOST: $(hostname)" >> "$MASTERLOG"
echo "SYSTEM: $(uname -a)" >> "$MASTERLOG"
echo "FSL VERSION: $(fslversion)" >> "$MASTERLOG"
echo "====================================" >> "$MASTERLOG"

while read SUB; do

    SUBNAME=$(basename "$SUB")

    echo "------------------------------------" | tee -a "$MASTERLOG"
    echo "SUBJECT: $SUBNAME" | tee -a "$MASTERLOG"
    echo "TIME: $(date)" | tee -a "$MASTERLOG"

    FUNC=$(find "$SUB/func" \
        -name "*task-rest*_bold.nii.gz" \
        | head -n 1)

    if [ ! -f "$FUNC" ]; then
        echo "$SUBNAME : MISSING FUNC FILE" | tee -a "$MASTERLOG"
        continue
    fi

    OUTDIR="$SUB/derivatives/mcflirt_v2"
    mkdir -p "$OUTDIR"

    OUTBASE="$OUTDIR/func_mc_v2"

    OUTNII="${OUTBASE}.nii.gz"
    OUTPAR="${OUTBASE}.par"

    LOGFILE="$OUTDIR/mcflirt_v2.log"

    ##################################################
    # Skip if already completed
    ##################################################

    if [ -f "$OUTNII" ] && [ -f "$OUTPAR" ]; then
        echo "$SUBNAME : SKIP (already complete)" | tee -a "$MASTERLOG"
        continue
    fi

    ##################################################
    # remove partial outputs
    ##################################################

    rm -rf "$OUTDIR"/*
    mkdir -p "$OUTDIR"

    echo "$SUBNAME : RUNNING MCFLIRT V2" | tee -a "$MASTERLOG"

    ##################################################
    # MCFLIRT
    ##################################################

    mcflirt \
        -in "$FUNC" \
        -out "$OUTBASE" \
        -plots \
        -report \
        -meanvol \
        -mats \
        -rmsabs \
        -rmsrel \
        > "$LOGFILE" 2>&1

    ##################################################
    # QC REPORT
    ##################################################

    {
        echo ""
        echo "=========== QC REPORT ==========="

        echo "Input:"
        echo "$FUNC"

        echo ""
        echo "Output:"
        echo "$OUTNII"

        echo ""
        echo "Volumes INPUT:"
        fslnvols "$FUNC"

        echo ""
        echo "Volumes OUTPUT:"
        fslnvols "$OUTNII"

        echo ""
        echo "Voxel Size INPUT:"
        fslinfo "$FUNC" | grep pixdim

        echo ""
        echo "Voxel Size OUTPUT:"
        fslinfo "$OUTNII" | grep pixdim

        echo ""
        echo "Dimensions OUTPUT:"
        fslinfo "$OUTNII" | grep -E "dim[1234]"

        echo "Reference volume: default MCFLIRT (middle volume unless -refvol specified)"

        echo ""
        echo "Output size:"
        ls -lh "$OUTNII"

        echo ""
        echo "Matrix directory:"
        ls "$OUTDIR" | grep ".mat" || true

        echo ""
        echo "Absolute RMS:"
        ls "$OUTDIR" | grep "abs.rms" || true

        echo ""
        echo "Relative RMS:"
        ls "$OUTDIR" | grep "rel.rms" || true

        echo ""
        echo "Finished:"
        date

    } >> "$MASTERLOG"

    ##################################################
    # Validation
    ##################################################

    if [ -f "$OUTNII" ] && [ -f "$OUTPAR" ]; then
        echo "$SUBNAME : SUCCESS" | tee -a "$MASTERLOG"
    else
        echo "$SUBNAME : FAILED" | tee -a "$MASTERLOG"
    fi

done < <(
    find "$BASE" -maxdepth 1 -type d -name "sub-*" | sort
)

echo "====================================" >> "$MASTERLOG"
echo "MCFLIRT V2 FINISHED: $(date)" >> "$MASTERLOG"
echo "====================================" >> "$MASTERLOG"
