#include "chelis_runtime.h"
#include "chelis_runtime_views.h"
#include "chelis_runtime_dtype.h"
#include "chelis_blas.h"
#include "chelis_simd.h"
#include "chelis_math.h"

int main(void) {
    const int64_t shape[] = {2};
    chelis_tensor *tensor = chelis_alloc(1, shape, CHELIS_DTYPE_F32);
    if (tensor == NULL) return 1;
    chelis_tensor_write *guard = chelis_tensor_begin_write(tensor);
    if (guard == NULL) return 2;
    chelis_write_view write = chelis_tensor_write_view(guard);
    if (write.count != 2 || write.dtype != CHELIS_DTYPE_F32) return 3;
    float *values = write.data;
    values[0] = 3.0f;
    values[1] = 4.0f;
    chelis_tensor_end_write(guard);
    chelis_read_view read = chelis_tensor_read_view(tensor);
    if (read.count != 2 || read.dtype != CHELIS_DTYPE_F32) return 4;
    const float *data = read.data;
    const float result = cblas_sdot(2, data, 1, data, 1);
    chelis_tensor_release(tensor);
    return result == 25.0f ? 0 : 5;
}
