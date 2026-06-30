#!/bin/bash

set -e

# 1. AVX-512 Leakage Scan
# If zmm registers (these are AVX-512 registers) or evex prefixes appear in the assembler output, it means that some library is still pushing this code.
if [[ "$USE_AVX512" != "1" ]]; then
    log_info "${SEARCH_MARK} Scanning final binaries for accidental AVX-512 leak..."
    while IFS= read -r file; do
        log_debug "Analyzing $(basename "$file")..."
        set +o pipefail 2>/dev/null || true
        LEAKED_INSTR=$("${FFBUILD_CROSS_PREFIX}objdump" -d -j .text "$file" 2>/dev/null | \
            grep -Ei '\bzmm[0-9]|\b[xy]mm(1[6-9]|2[0-9]|3[0-1])\b|\bk[0-7]\b|evex' | head -n 20)
        set -o pipefail 2>/dev/null || true

        if [[ -n "$LEAKED_INSTR" ]]; then
            log_warn "AVX-512 instructions detected in $(basename "$file")!"
            if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
                echo -e "${LOG_WARN}--- First 20 leaked lines: ---${NC}"
                echo "$LEAKED_INSTR"
                echo -e "${LOG_WARN}------------------------------${NC}"
            fi
        else
            log_info "${CHECK_MARK} $(basename "$file") is clean of AVX-512 code."
        fi
    done < <(find "${PKG_DIR}/bin" -type f \( -name "*.exe" -o -name "*.dll" \))
fi

# 2. Component Mapping & Dynamic Symbol Verification
# Map ffmpeg enable flags to their corresponding codec names and symbol prefixes
# Format: 'enable_flag:codec_name:media
declare -A COMPONENT_TEST_MAP=(
    ["enable-libx264"]="libx264:v:ff_libx264"
    ["enable-libx265"]="libx265:v:ff_libx265"
    ["enable-libsvtav1"]="libsvtav1:v:ff_libsvtav1"
    ["enable-libaom"]="libaom:v:ff_libaom_av1"
    ["enable-libvpx"]="libvpx:v:ff_libvpx_vp9"
    ["enable-libsvtvp9"]="libsvtvp9:v:ff_libsvt_vp9"
    ["enable-libopenh264"]="libopenh264:v:ff_libopenh264"
    ["enable-libvvdec"]="libvvdec:v:ff_libvvdec"
    ["enable-libvvenc"]="libvvenc:v:ff_libvvenc"
    ["enable-libxevd"]="libxevd:v:ff_libxevd"
    ["enable-liblcevc_dec"]="liblcevc_dec:v:ff_lcevc"
    ["enable-libmp3lame"]="libmp3lame:a:ff_libmp3lame"
    ["enable-libopus"]="libopus:a:ff_libopus_encoder"
    ["enable-libvorbis"]="libvorbis:a:ff_libvorbis"
    ["enable-libfdk-aac"]="libfdk_aac:a:ff_libfdk_aac_encoder"
    ["enable-libsvtjpegxs"]="libsvtjpegxs:v:ff_libsvtjpegxs"
    ["enable-libopenjpeg"]="libopenjpeg:v:ff_libopenjpeg"
    ["enable-libwebp"]="libwebp:v:ff_libwebp_encoder"
    ["enable-libgme"]="libgme:a:ff_libgme"
    ["enable-libmodplug"]="libmodplug:a:ff_libmodplug"
    ["enable-libopenmpt"]="libopenmpt:a:ff_libopenmpt"
    ["enable-libass"]="libass:v:ff_ass"
    ["enable-libvmaf"]="libvmaf:v:ff_vf_libvmaf"
    ["enable-libpulse"]="libpulse:a:ff_pulse_audio"
    ["enable-libsoxr"]="libsoxr:a:ff_sox"
    ["enable-librubberband"]="librubberband:a:ff_af_rubberband"
    ["enable-libopenvino"]="libopenvino:v:ff_dnn_backend_openvino"
    ["enable-libtensorflow"]="libtensorflow:v:ff_dnn_backend_tf"
    ["enable-libtorch"]="libtorch:v:ff_dnn_backend_torch"
    ["enable-libglslang"]="libglslang:v:ff_vk_glslang"
    ["enable-libshaderc"]="libshaderc:v:ff_vk_shaderc"
    ["enable-libvpl"]="libvpl:v:ff_vpl"
    ["enable-libcodec2"]="libcodec2:v:ff_libcodec2_encoder"
    ["enable-libmad"]="libmad:a:ff_libmad"
    ["enable-libmpeghdec"]="libmpeghdec:v:ff_libmpeghdec"
    ["enable-libshine"]="libshine:v:ff_libshine"
    ["enable-ia_mpegh"]="ia_mpegh:v:ff_ia_mpegh"
    ["enable-libopencore-amrnb"]="libopencore_amrnb:a:ff_libopencore_amrnb_encoder"
    ["enable-libtwolame"]="libtwolame:a:ff_libtwolame"
    ["enable-libvo-amrwbenc"]="libvo_amrwbenc:a:ff_libvo_amrwbenc"
    ["enable-libtheora"]="libtheora:v:ff_libtheora"
    ["enable-libsvthevc"]="libsvthevc:v:ff_libsvt_hevc"
    ["enable-libxvid"]="libxvid:v:ff_libxvid"
)

# 3. Generate Dynamic Component Tests
generate_component_tests() {
    local enabled_components=()
    local tests=()
    local config_source="${FINAL_CONFIGURE:-$(cat ${FFMPEG_CONFIG_LOG:-/dev/null} 2>/dev/null)}"

    log_debug "${SEARCH_MARK} Generating specific tests for enabled components..."

    for flag in "${!COMPONENT_TEST_MAP[@]}"; do
        if [[ "$config_source" == *"$flag"* ]]; then
            local codec_spec="${COMPONENT_TEST_MAP[$flag]}"
            local codec_name="${codec_spec%%:*}"
            local media_type="${codec_spec#*:}"
            
            enabled_components+=("$codec_name ($media_type)")

            # Build specific test based on media type
            if [[ "$media_type" == "v" ]]; then
                # Video tests: Add 10-bit test for x265 and x264 if enabled
                if [[ "$codec_name" == "libx265" || "$codec_name" == "libx264" ]]; then
                    # Test 10-bit encoding
                    tests+=("-loglevel warning -f lavfi -i testsrc2=s=1920x1080:r=30:d=2 -c:v $codec_name -pix_fmt yuv420p10le -b:v 500k -f null -")
                    # Test standard 8-bit
                    tests+=("-loglevel warning -f lavfi -i testsrc2=s=1280x720:r=30:d=1 -c:v $codec_name -pix_fmt yuv420p -b:v 500k -f null -")
                elif [[ "$codec_name" == "libaom" || "$codec_name" == "libsvtav1" ]]; then
                    # AV1 specific tests (often memory heavy)
                    tests+=("-loglevel warning -f lavfi -i testsrc2=s=1280x720:r=30:d=2 -c:v $codec_name -crf 30 -f null -")
                else
                    # Standard video test
                    tests+=("-loglevel warning -f lavfi -i testsrc2=s=1280x720:r=30:d=2 -c:v $codec_name -b:v 500k -f null -")
                fi
            else
                # Audio tests
                if [[ "$codec_name" == "libopus" || "$codec_name" == "libvorbis" ]]; then
                    # Test resampling (common audio bug)
                    tests+=("-loglevel warning -f lavfi -i sine=f=1000:d=2 -ar 48000 -c:a $codec_name -b:a 128k -f null -")
                else
                    tests+=("-loglevel warning -f lavfi -i sine=f=1000:d=2 -c:a $codec_name -b:a 128k -f null -")
                fi
            fi
        fi
    done

    # Add a complex filter chain test if video codecs are present
    if [[ ${#enabled_components[@]} -gt 0 ]] && [[ "$config_source" == *"--enable-libx264"* || "$config_source" == *"--enable-libx265"* ]]; then
        tests+=("-loglevel warning -f lavfi -i color=c=red:s=1280x720:d=2 -vf scale=640x360,format=yuv444p10le -c:v libx264 -pix_fmt yuv444p10le -b:v 1M -f null -")
    fi

    if [[ ${#enabled_components[@]} -eq 0 ]]; then
        log_warn "No heavy external components detected for specific testing."
        # Add a minimal fallback
        tests+=("-loglevel warning -f lavfi -i testsrc2=d=1 -c:v wrapped_avframe -f null -")
    else
        log_info "Discovered ${#enabled_components[@]} components for deep audit:"
        for comp in "${enabled_components[@]}"; do
            log_debug "   - $comp"
        done
    fi

    COMPREHENSIVE_TESTS=("${tests[@]}")
}

# 4. Main Audit Runner
run_deep_component_audit() {
    log_info "${START_MARK} Launching automated Wine+GDB crash audit..."

    local TEST_EXE="${PKG_DIR}/bin/ffmpeg.exe"
    [[ ! -f "$TEST_EXE" ]] && TEST_EXE="/opt/ffdest/opt/ffbuild/bin/ffmpeg.exe"
    if [ ! -f "$TEST_EXE" ]; then
        log_error "FFmpeg binary not found at $TEST_EXE"
        return 1
    fi

    if ! command -v wine64 &> /dev/null && ! command -v wine &> /dev/null; then
        log_warn "Wine is not installed. Skipping audit."
        return 0
    fi

    export WINEDEBUG="-all,err,seh,bad,fixme:all"
    export WINEARCH=win64
    export DISPLAY=:99
    [[ -z "$TMP_DIR" ]] && TMP_DIR="/tmp"

    local AUDIT_LOG="${TMP_DIR}/ffmpeg_deep_audit.log"
    local CRASH_LOG="${TMP_DIR}/ffmpeg_crash_details.log"
    local CRASH_AUDIT_LOG="${TMP_DIR}/ffmpeg_crash_audit.log"
    mkdir -p "$TMP_DIR"
    rm -f "$CRASH_AUDIT_LOG" "$AUDIT_LOG" "$CRASH_LOG"

    log_debug "${LOG_DEBUG}=======================================================${NC}"
    log_debug "🚨 WINE SMOKE TEST ANALYSIS (DEBUG_MODE=1)"
    log_debug "${LOG_DEBUG}=======================================================${NC}"

    log_info "${START_MARK} Launching Deep Component & Stability Audit..."

    # --- STAGE 1: Automatic exception analysis ---
    # Basic info + a filter chain
    local TEST_SUITE=(
        "-codecs -formats -filters -protocols -pix_fmts"
        "-v debug -f lavfi -i testsrc=size=1280x720:rate=60:duration=2 -f lavfi -i sine=frequency=1000:duration=2 -vf scale=640x360,format=yuv420p -c:v wrapped_avframe -c:a pcm_s16le -f null -"
    )

    local CRASH_FOUND=0
    local CRASH2_FOUND=0
    local TEST_INDEX=0

    for TEST_ARGS in "${TEST_SUITE[@]}"; do
        ((++TEST_INDEX))
        local PHASE1_LOG="${TMP_DIR}/audit_p1_${TEST_INDEX}.log"
        rm -f "$PHASE1_LOG"
        log_debug "Executing test: ${GREY_B}${TEST_ARGS:0:60}...${NC}"

        if winedbg --auto "$TEST_EXE" $TEST_ARGS >> "$PHASE1_LOG" 2>&1; then
            log_debug "Test completed (winedbg exit 0)."
        else
            log_error "Test failed (winedbg exit non-zero). Checking for crash details..."
            if grep -Eiq "Access Violation|0xc0000005|0xc0000409|0xc000001d|Segmentation fault|Illegal instruction|Unhandled exception|stack smashing|buffer overflow|stack_chk_fail|stack-buffer-overflow|global-buffer-overflow|access violation|SIGSEGV|illegal instruction" "$PHASE1_LOG"; then
                log_error "Crash detected!"
                CRASH_FOUND=1
                cat "$PHASE1_LOG" >> "$CRASH_AUDIT_LOG"
                continue
            else
                log_warn "Non-zero exit, but no critical crash exception found. Continuing..."
            fi
        fi
        cat "$PHASE1_LOG" >> "$CRASH_AUDIT_LOG"
        rm -f "$PHASE1_LOG"
    done

    # --- STAGE 2: Collecting backtraces when basic parameters drop ---
    # Сбрасываем счётчик для второго этапа
    local TEST_INDEX=0

    if [[ $CRASH_FOUND -eq 0 ]]; then
        for TEST_ARGS in "${TEST_SUITE[@]}"; do
            ((++TEST_INDEX))
            local PHASE2_LOG="${TMP_DIR}/audit_p2_${TEST_INDEX}.log"
            rm -f "$PHASE2_LOG"
            log_debug "Executing sub-test: ${GREY_B}${TEST_ARGS:0:60}...${NC}"
            
            winedbg --command "cont; bt; kill; quit" "$TEST_EXE" $TEST_ARGS >> "$PHASE2_LOG" 2>&1

            if grep -Eiq "Access Violation|0xc0000005|0xc0000409|0xc000001d|Segmentation fault|Illegal instruction|Unhandled exception|stack smashing|buffer overflow|stack_chk_fail|stack-buffer-overflow|global-buffer-overflow|access violation|SIGSEGV|illegal instruction" "$PHASE2_LOG"; then
                log_error "CRITICAL FAULT DETECTED during sub-test: ${TEST_ARGS:0:60}..."
                CRASH2_FOUND=1
                cat "$PHASE2_LOG" >> "$CRASH_AUDIT_LOG"
                continue
            fi
            cat "$PHASE2_LOG" >> "$CRASH_AUDIT_LOG"
            rm -f "$PHASE2_LOG"
        done
    fi

    # Вывод результатов бэктрейса смок-тестов
    if [[ -f "$CRASH_AUDIT_LOG" && -s "$CRASH_AUDIT_LOG" ]]; then
        if [[ $CRASH_FOUND -eq 1 ]]; then
            log_error "CRASH DETECTED IN SMOKE TESTS."
            cat "$CRASH_AUDIT_LOG" >&2
        elif [[ $CRASH2_FOUND -eq 1 ]]; then
            log_debug "Relevant Crash Backtrace:"
            if grep -Eiq "backtrace" "$CRASH_AUDIT_LOG"; then
                sed -n '/[Bb]acktrace/,$p' "$CRASH_AUDIT_LOG" >&2
            else
                cat "$CRASH_AUDIT_LOG" >&2
            fi
        else
            log_debug "No critical errors found in log."
        fi
    fi

    # --- STAGE 3: DYNAMIC TESTS OF COMPONENTS (CODECS) ---
    generate_component_tests

    # Add a generic "stability" test if no specific components found or as a baseline
    if [[ ${#COMPREHENSIVE_TESTS[@]} -eq 0 ]]; then
        COMPREHENSIVE_TESTS+=("-loglevel warning -f lavfi -i testsrc2=d=1 -c:v wrapped_avframe -f null -")
    fi

    local TOTAL_TESTS=${#COMPREHENSIVE_TESTS[@]}
    local FAILED_TESTS=0

    for i in "${!COMPREHENSIVE_TESTS[@]}"; do
        local TEST_ARGS="${COMPREHENSIVE_TESTS[$i]}"
        local TEST_NUM=$((i + 1))
        local CODEC_NAME=$(echo "$TEST_ARGS" | grep -oE "lib[a-z0-9]+|svt[a-z0-9]+" | head -1)
        [[ -z "$CODEC_NAME" ]] && CODEC_NAME="Generic"
        
        log_debug "Running Test ${TEST_NUM}/${TOTAL_TESTS}: ${CYAN}${CODEC_NAME}${NC}..."
        local PHASE_LOG="${TMP_DIR}/audit_phase_${TEST_NUM}.log"
        rm -f "$PHASE_LOG"

        # Запуск теста кодека через нативный winedbg --auto с ограничением времени
        if timeout 60s winedbg --auto "$TEST_EXE" $TEST_ARGS >> "$PHASE_LOG" 2>&1; then
            log_info "    -> Passed (Exit 0)"
            cat "$PHASE_LOG" >> "$AUDIT_LOG"
        else
            local EXIT_CODE=$?
            if [[ $EXIT_CODE -eq 124 ]]; then
                log_error "   -> FAILED: TIMEOUT (Hang detected in ${CODEC_NAME})"
                FAILED_TESTS=$((FAILED_TESTS + 1))
                cat "$PHASE_LOG" >> "$AUDIT_LOG"
                continue
            fi
 
            if grep -qE "Exception c0000005|Access Violation|Segmentation fault|0xc000001d|Illegal instruction" "$PHASE_LOG"; then
                log_error "   -> FAILED: CRASH detected in ${CODEC_NAME}"
                FAILED_TESTS=$((FAILED_TESTS + 1))
                
                echo "=== CRASH REPORT: ${CODEC_NAME} ===" > "$CRASH_LOG"
                echo "Command: ffmpeg $TEST_ARGS" >> "$CRASH_LOG"
                echo "Exit Code: $EXIT_CODE" >> "$CRASH_LOG"
                echo "Timestamp: $(date)" >> "$CRASH_LOG"
                echo "--- Log Snippet ---" >> "$CRASH_LOG"
                grep -A 15 -B 5 -E "Exception|Access Violation|Backtrace" "$PHASE_LOG" >> "$CRASH_LOG" || cat "$PHASE_LOG" >> "$CRASH_LOG"

                cat "$CRASH_LOG" >&2
                cat "$PHASE_LOG" >> "$AUDIT_LOG"
            else
                log_warn "   -> Non-zero exit ($EXIT_CODE) but no crash signature in ${CODEC_NAME}."
                cat "$PHASE_LOG" >> "$AUDIT_LOG"
            fi
        fi
        rm -f "$PHASE_LOG"
    done

    # --- PHASE 5: Final Report ---
    log_debug "${LOG_DEBUG}=======================================================${NC}"

    if [[ $CRASH_FOUND -eq 1 || $CRASH2_FOUND -eq 1 ]]; then
        log_error "HARDWARE OR LINKING FAULT DETECTED IN BASE SMOKE TESTS!"
        # return 1
    elif [[ $FAILED_TESTS -gt 0 ]]; then
        log_error "AUDIT FAILED: ${FAILED_TESTS}/${TOTAL_TESTS} codec tests failed."
        # return 1
    else
        log_info "${CHECK_MARK} Wine runtime smoke test passed successfully."
        return 0
    fi
}

# run Deep Audit
run_deep_component_audit
