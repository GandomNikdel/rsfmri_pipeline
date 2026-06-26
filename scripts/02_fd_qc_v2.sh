#!/bin/bash
###############################################################################
#
# Pipeline : Resting-state fMRI preprocessing (Version 2)
#
# Step     : 02 - Framewise Displacement Quality Control
#
# Purpose  :
#   Compute framewise displacement (FD) from motion-corrected fMRI data
#   using FSL fsl_motion_outliers and generate:
#
#       • FD metric
#       • Outlier regressors
#       • QC plots
#       • Subject QC reports
#       • Dataset summary
#
#
# Version  : 2.0.0
#
###############################################################################

set -euo pipefail

##############################
# PROJECT
##############################

BASE=~/wrkdir/HBNFINAL

cd "$BASE"

##############################
# PIPELINE VERSION
##############################

PIPELINE_VERSION="2.0.0"

STEP_NAME="FD_QC_V2"

##############################
# Threshold
##############################

FD_THRESHOLD=0.30

##############################
# LOG DIRECTORY
##############################

LOGDIR="$BASE/logs"

mkdir -p "$LOGDIR"

MASTERLOG="$LOGDIR/fd_qc_v2_master.log"

DATASETSUMMARY="$LOGDIR/fd_dataset_summary_v2.tsv"

##############################
# MASTER HEADER
##############################

{

echo "==============================================================="
echo "PIPELINE VERSION : $PIPELINE_VERSION"
echo "STEP             : $STEP_NAME"
echo "START            : $(date)"
echo "HOST             : $(hostname)"
echo "SYSTEM           : $(uname -a)"
echo "FSL VERSION      : $(fslversion)"
echo "FD THRESHOLD     : ${FD_THRESHOLD}"
echo "==============================================================="

} >> "$MASTERLOG"

##############################
# DATASET SUMMARY HEADER
##############################

echo -e \
"Subject\tVolumes\tMeanFD\tMedianFD\tSDFD\tMinFD\tMaxFD\tOutliers\tPercentOutliers\tStatus" \
> "$DATASETSUMMARY"

###############################################################################
#
# SUBJECT LOOP
#
###############################################################################

find "$BASE" -maxdepth 1 -type d -name "sub-*" | sort | while read SUB
do

    SUBJECT=$(basename "$SUB")

    echo "--------------------------------------------------------" | tee -a "$MASTERLOG"
    echo "SUBJECT : $SUBJECT" | tee -a "$MASTERLOG"
    echo "START   : $(date)" | tee -a "$MASTERLOG"

    ############################################################
    # INPUT
    ############################################################

    FUNC="$SUB/derivatives/mcflirt_v2/func_mc_v2.nii.gz"

    PAR="$SUB/derivatives/mcflirt_v2/func_mc_v2.par"

    ############################################################
    # OUTPUT DIRECTORY
    ############################################################

    OUTDIR="$SUB/derivatives/fd_qc_v2"

    mkdir -p "$OUTDIR"

    ############################################################
    # OUTPUT FILES
    ############################################################

    FD_CONFOUNDS="$OUTDIR/fd_outliers_v2.txt"

    FD_METRIC="$OUTDIR/fd_metric_v2.txt"

    FD_PLOT="$OUTDIR/fd_plot_v2.png"

    SUBJECTLOG="$OUTDIR/fd_qc_v2.log"

    ############################################################
    # CHECK INPUTS
    ############################################################

    if [[ ! -f "$FUNC" ]]; then

        echo "$SUBJECT : Missing func_mc_v2.nii.gz" | tee -a "$MASTERLOG"

        echo -e "${SUBJECT}\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tMISSING_FUNC" \
        >> "$DATASETSUMMARY"

        continue

    fi

    if [[ ! -f "$PAR" ]]; then

        echo "$SUBJECT : Missing motion parameter (.par)" | tee -a "$MASTERLOG"

        echo -e "${SUBJECT}\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tMISSING_PAR" \
        >> "$DATASETSUMMARY"

        continue

    fi

    ############################################################
    # SKIP FINISHED SUBJECTS
    ############################################################

    if [[ -f "$FD_CONFOUNDS" && -f "$FD_METRIC" && -f "$FD_PLOT" ]]; then

        echo "$SUBJECT : Already processed -> SKIP" | tee -a "$MASTERLOG"

        continue

    fi

    ############################################################
    # REMOVE PARTIAL OUTPUTS
    ############################################################

    rm -f "$FD_CONFOUNDS"

    rm -f "$FD_METRIC"

    rm -f "$FD_PLOT"

    rm -f "$SUBJECTLOG"

    echo "$SUBJECT : Running FD QC..." | tee -a "$MASTERLOG"


############################################################
# STEP 3 — FRAMEWISE DISPLACEMENT (FD)
############################################################

echo "Running Framewise Displacement..." | tee -a "$MASTERLOG"

if fsl_motion_outliers \
    -i "$FUNC" \
    --fd \
    --nomoco \
    --thresh=${FD_THRESHOLD} \
    -o "$FD_CONFOUNDS" \
    -s "$FD_METRIC" \
    -p "$FD_PLOT" \
    > "$SUBJECTLOG" 2>&1
then
    FD_EXIT=0
else
    FD_EXIT=$?
fi

############################################################
# VALIDATION
############################################################

if [[ $FD_EXIT -ne 0 ]]; then

    echo "$SUBJECT : FD computation FAILED" | tee -a "$MASTERLOG"

    echo -e \
"${SUBJECT}\tNA\tNA\tNA\tNA\tNA\tNA\tFAILED" \
>> "$DATASETSUMMARY"

    continue

fi

############################################################
# IMPORTANT NOTE
############################################################
# طبق مستندات رسمی FSL اگر هیچ Volume ای Outlier نباشد،
# فایل Confound ساخته نمی‌شود.
#
# بنابراین نبودن fd_outliers_v2.txt خطا نیست.
############################################################

if [[ ! -f "$FD_METRIC" ]]; then

    echo "$SUBJECT : FD metric missing." | tee -a "$MASTERLOG"

    echo -e \
"${SUBJECT}\tNA\tNA\tNA\tNA\tNA\tNA\tFAILED" \
>> "$DATASETSUMMARY"

    continue

fi

############################################################
# Number of outlier volumes
############################################################

if [[ -f "$FD_CONFOUNDS" ]]; then

    FD_OUTLIERS=$(awk '{sum+=$1} END{print sum+0}' "$FD_CONFOUNDS")

else

    FD_OUTLIERS=0

fi

echo "$SUBJECT : FD finished successfully." | tee -a "$MASTERLOG"


############################################################
# STEP 4 — QC METRICS
############################################################

python3 << EOF

import numpy as np

metric_file = "$FD_METRIC"
report_file = "$OUTDIR/fd_qc_report_v2.tsv"

# ---------- Robust loading ----------
if (not os.path.exists(metric_file)) or os.path.getsize(metric_file) == 0:
    raise RuntimeError(f"FD metric file is missing or empty: {metric_file}")

fd = np.loadtxt(metric_file)

if np.ndim(fd) == 0:
    fd = np.array([fd])

nvol = len(fd)

############################################################
# Basic statistics
############################################################

nvol = len(fd)

mean_fd   = float(np.mean(fd))
median_fd = float(np.median(fd))
std_fd    = float(np.std(fd))

min_fd = float(np.min(fd))
max_fd = float(np.max(fd))

############################################################
# Percentiles
############################################################

p95 = float(np.percentile(fd,95))
p99 = float(np.percentile(fd,99))

############################################################
# Outliers
############################################################

threshold = float($FD_THRESHOLD)

n_outliers = int(np.sum(fd > threshold))

percent_outliers = 100.0 * n_outliers / nvol

remaining = nvol - n_outliers

############################################################
# Save metrics
############################################################

with open(metrics_file,"w") as f:

    f.write("Metric\tValue\n")

    f.write(f"Subject\t$SUBJECT\n")

    f.write(f"Volumes\t{nvol}\n")

    f.write(f"Threshold\t{threshold:.3f}\n")

    f.write(f"MeanFD\t{mean_fd:.6f}\n")

    f.write(f"MedianFD\t{median_fd:.6f}\n")

    f.write(f"SDFD\t{std_fd:.6f}\n")

    f.write(f"MinimumFD\t{min_fd:.6f}\n")

    f.write(f"MaximumFD\t{max_fd:.6f}\n")

    f.write(f"P95FD\t{p95:.6f}\n")

    f.write(f"P99FD\t{p99:.6f}\n")

    f.write(f"OutlierVolumes\t{n_outliers}\n")

    f.write(f"PercentOutliers\t{percent_outliers:.3f}\n")

    f.write(f"RemainingVolumes\t{remaining}\n")

EOF

echo "$SUBJECT : QC metrics computed." | tee -a "$MASTERLOG"

############################################################
# STEP 5 — SUBJECT REPORT
############################################################

METRICSFILE="$OUTDIR/fd_metrics_v2.tsv"

SUBJECTREPORT="$OUTDIR/fd_qc_report_v2.tsv"

############################################################
# Check metrics file
############################################################

if [[ ! -f "$METRICSFILE" ]]; then

    echo "$SUBJECT : Missing fd_metrics_v2.tsv" | tee -a "$MASTERLOG"

    continue

fi

############################################################
# Create Subject Report
############################################################

cp "$METRICSFILE" "$SUBJECTREPORT"

############################################################
# Append metadata
############################################################

{

echo ""

echo "----------------------------------------"

echo "PipelineVersion	${PIPELINE_VERSION}"

echo "Step	FD_QC_V2"

echo "FSLVersion	$(fslversion)"

echo "Hostname	$(hostname)"

echo "Date	$(date)"

echo "Status	PASS"

} >> "$SUBJECTREPORT"

############################################################
# Log
############################################################

echo "$SUBJECT : Subject report created." | tee -a "$MASTERLOG"

############################################################
# STEP 6 — DATASET SUMMARY
############################################################

echo "Building Dataset Summary..." | tee -a "$MASTERLOG"

echo -e \
"Subject\tVolumes\tMeanFD\tMedianFD\tSDFD\tMinimumFD\tMaximumFD\tP95FD\tP99FD\tOutlierVolumes\tPercentOutliers\tRemainingVolumes\tStatus" \
> "$DATASETSUMMARY"

find "$BASE" -type f -name "fd_metrics_v2.tsv" | sort | while read METRICS
do

    SUBJECT=$(awk -F'\t' '$1=="Subject"{print $2}' "$METRICS")

    VOLUMES=$(awk -F'\t' '$1=="Volumes"{print $2}' "$METRICS")

    MEANFD=$(awk -F'\t' '$1=="MeanFD"{print $2}' "$METRICS")

    MEDIANFD=$(awk -F'\t' '$1=="MedianFD"{print $2}' "$METRICS")

    SDFD=$(awk -F'\t' '$1=="SDFD"{print $2}' "$METRICS")

    MINFD=$(awk -F'\t' '$1=="MinimumFD"{print $2}' "$METRICS")

    MAXFD=$(awk -F'\t' '$1=="MaximumFD"{print $2}' "$METRICS")

    P95FD=$(awk -F'\t' '$1=="P95FD"{print $2}' "$METRICS")

    P99FD=$(awk -F'\t' '$1=="P99FD"{print $2}' "$METRICS")

    OUTLIERS=$(awk -F'\t' '$1=="OutlierVolumes"{print $2}' "$METRICS")

    PERCENT=$(awk -F'\t' '$1=="PercentOutliers"{print $2}' "$METRICS")

    REMAINING=$(awk -F'\t' '$1=="RemainingVolumes"{print $2}' "$METRICS")

    STATUS="PASS"

    echo -e \
"${SUBJECT}\t${VOLUMES}\t${MEANFD}\t${MEDIANFD}\t${SDFD}\t${MINFD}\t${MAXFD}\t${P95FD}\t${P99FD}\t${OUTLIERS}\t${PERCENT}\t${REMAINING}\t${STATUS}" \
>> "$DATASETSUMMARY"

done

echo "Dataset Summary completed." | tee -a "$MASTERLOG"

############################################################
# STEP 7 — FINAL VALIDATION
############################################################

echo "Running Final Validation..." | tee -a "$MASTERLOG"

TOTAL=0
SUCCESS=0
FAILED=0

while read SUB
do

    SUBJECT=$(basename "$SUB")

    OUTDIR="$SUB/derivatives/fd_qc_v2"

    STATUS="PASS"

    ########################################################
    # Required outputs
    ########################################################

    REQUIRED=(
        "$OUTDIR/fd_metric_v2.txt"
        "$OUTDIR/fd_metrics_v2.tsv"
        "$OUTDIR/fd_qc_report_v2.tsv"
        "$OUTDIR/fd_plot_v2.png"
        "$OUTDIR/fd_qc_v2.log"
    )

    for FILE in "${REQUIRED[@]}"
    do
        if [[ ! -f "$FILE" ]]; then

            STATUS="FAIL"

            echo "$SUBJECT : Missing $(basename "$FILE")" \
            | tee -a "$MASTERLOG"

        fi
    done

    ########################################################
    # fd_outliers_v2.txt
    ########################################################
    # این فایل الزامی نیست.
    # طبق مستندات رسمی FSL اگر هیچ Outlier وجود نداشته باشد
    # اصلاً تولید نمی‌شود.
    ########################################################

    TOTAL=$((TOTAL+1))

    if [[ "$STATUS" == "PASS" ]]; then

        SUCCESS=$((SUCCESS+1))

    else

        FAILED=$((FAILED+1))

    fi

done < <(
    find "$BASE" -maxdepth 1 -type d -name "sub-*" | sort
)

############################################################
# Final validation summary
############################################################

echo "" | tee -a "$MASTERLOG"

echo "===================================================" | tee -a "$MASTERLOG"

echo "FINAL VALIDATION SUMMARY" | tee -a "$MASTERLOG"

echo "Subjects checked : $TOTAL" | tee -a "$MASTERLOG"

echo "Successful       : $SUCCESS" | tee -a "$MASTERLOG"

echo "Failed           : $FAILED" | tee -a "$MASTERLOG"

echo "===================================================" | tee -a "$MASTERLOG"

############################################################
# STEP 8 — FINAL MASTER REPORT
############################################################

PIPELINE_END=$(date)

echo "" >> "$MASTERLOG"
echo "===============================================================" >> "$MASTERLOG"
echo "PIPELINE FINISHED" >> "$MASTERLOG"
echo "===============================================================" >> "$MASTERLOG"

echo "Pipeline Version : $PIPELINE_VERSION" >> "$MASTERLOG"
echo "Step             : $STEP_NAME" >> "$MASTERLOG"

echo "" >> "$MASTERLOG"

echo "Start Time       : $(head -20 "$MASTERLOG" | grep "START" | head -1 | cut -d':' -f2-)" >> "$MASTERLOG"
echo "End Time         : $PIPELINE_END" >> "$MASTERLOG"

echo "" >> "$MASTERLOG"

echo "Subjects Checked : $TOTAL" >> "$MASTERLOG"
echo "Successful       : $SUCCESS" >> "$MASTERLOG"
echo "Failed           : $FAILED" >> "$MASTERLOG"

echo "" >> "$MASTERLOG"

echo "FD Threshold     : $FD_THRESHOLD mm" >> "$MASTERLOG"
echo "FSL Version      : $(fslversion)" >> "$MASTERLOG"
echo "Hostname         : $(hostname)" >> "$MASTERLOG"

echo "" >> "$MASTERLOG"

echo "Dataset Summary  : $DATASETSUMMARY" >> "$MASTERLOG"

echo "===============================================================" >> "$MASTERLOG"

echo ""
echo "FD QC Pipeline completed successfully."
echo "Master log:"
echo "$MASTERLOG"

echo ""

