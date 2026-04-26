From 334e68b202904a407d639a1c37db29d8bb3754d5 Mon Sep 17 00:00:00 2001
From: Jamaika1 <lukaszcz18@wp.pl>
Date: Tue, 6 Jan 2026 11:05:20 +0100
Subject: [PATCH] Jamaika1 patches 1-4

```
diff --git a/ggml/src/ggml-opencl/ggml-opencl.cpp b/ggml/src/ggml-opencl/ggml-opencl.cpp
index c87a32383c8..2c5b7710064 100644
--- a/ggml/src/ggml-opencl/ggml-opencl.cpp
+++ b/ggml/src/ggml-opencl/ggml-opencl.cpp
@@ -6046,8 +6046,10 @@ static void ggml_cl_mul_mat_id(ggml_backend_t backend, const ggml_tensor * src0,
                 GGML_ASSERT(false && "TODO: Unknown GPU");
             }
 
+#ifdef GGML_OPENCL_SOA_Q
             CL_CHECK(clSetKernelArg(kernel,  0, sizeof(cl_mem),   &extra0_q4_0->q));
             CL_CHECK(clSetKernelArg(kernel,  1, sizeof(cl_mem),   &extra0_q4_0->d));
+#endif
             CL_CHECK(clSetKernelArg(kernel,  2, sizeof(cl_mem),   &extra1->data_device));
             CL_CHECK(clSetKernelArg(kernel,  3, sizeof(cl_ulong), &offset1));
             CL_CHECK(clSetKernelArg(kernel,  4, sizeof(cl_mem),   &extra2->data_device));
diff --git a/ggml/src/ggml-cuda/common.cuh b/ggml/src/ggml-cuda/common.cuh
index 62e618850bf..70be95f0879 100644
--- a/ggml/src/ggml-cuda/common.cuh
+++ b/ggml/src/ggml-cuda/common.cuh
@@ -25,6 +25,7 @@
 #include <cassert>
 #include <cfloat>
 #include <cstdio>
+#include <limits>
 #include <string>
 #include <unordered_map>
 #include <vector>
diff --git a/ggml/src/ggml-cuda/ggml-cuda.cu b/ggml/src/ggml-cuda/ggml-cuda.cu
index 55e1c20c963..80a57698b13 100644
--- a/ggml/src/ggml-cuda/ggml-cuda.cu
+++ b/ggml/src/ggml-cuda/ggml-cuda.cu
@@ -3246,7 +3246,7 @@ static void evaluate_and_capture_cuda_graph(ggml_backend_cuda_context * cuda_ctx
 
             for (int i = 1; i <= concurrent_event->n_streams; ++i) {
                 cudaStream_t stream = cuda_ctx->stream(cuda_ctx->device, i);
-                CUDA_CHECK(cudaStreamWaitEvent(stream, concurrent_event->fork_event));
+                CUDA_CHECK(cudaStreamWaitEvent(stream, concurrent_event->fork_event, 0));
             }
         }
     };
@@ -3327,7 +3327,7 @@ static void evaluate_and_capture_cuda_graph(ggml_backend_cuda_context * cuda_ctx
                             // Wait on join events of forked streams in the main stream
                             CUDA_CHECK(cudaEventRecord(concurrent_event->join_events[i - 1],
                                                        cuda_ctx->stream(cuda_ctx->device, i)));
-                            CUDA_CHECK(cudaStreamWaitEvent(cuda_ctx->stream(), concurrent_event->join_events[i - 1]));
+                            CUDA_CHECK(cudaStreamWaitEvent(cuda_ctx->stream(), concurrent_event->join_events[i - 1], 0));
                         }
 
                         is_concurrent_event_active = false;
diff --git a/ggml/src/ggml-cuda/fattn-common.cuh b/ggml/src/ggml-cuda/fattn-common.cuh
index 8dc82a9d3b8..57a9781248d 100644
--- a/ggml/src/ggml-cuda/fattn-common.cuh
+++ b/ggml/src/ggml-cuda/fattn-common.cuh
@@ -4,6 +4,7 @@
 #include "convert.cuh"
 #include "vecdotq.cuh"
 
+#include <cmath>
 #include <cstdint>
 
 #define FATTN_KQ_STRIDE       256
@@ -595,7 +596,7 @@ static __global__ void flash_attn_mask_to_KV_max(
 #pragma unroll
         for (int j = 0; j < ncols1; ++j) {
             const float2 tmp = __half22float2(mask[j*s31 + KV_max_sj/2 + tid]);
-            all_inf = all_inf && int(isinf(tmp.x)) && int(isinf(tmp.y));
+            all_inf = all_inf && int(std::isinf(tmp.x)) && int(std::isinf(tmp.y));
         }
 
         all_inf = warp_reduce_all(all_inf);