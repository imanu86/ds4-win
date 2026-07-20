if(NOT WIN32)
    add_executable(ds4_test ds4_test.c)
    target_link_libraries(ds4_test PRIVATE
        ds4
        ds4_cuda
        CUDA::cudart
        CUDA::cublas
    )
    add_test(NAME ds4_test COMMAND ds4_test)
endif()

add_executable(ds4_bake_test ds4_bake_test.c)
target_link_libraries(ds4_bake_test PRIVATE ds4_bake)
add_test(NAME ds4_bake_test COMMAND ds4_bake_test)

add_executable(test_g130_ssdwrap_faults test_g130_ssdwrap_faults.c)
target_compile_definitions(test_g130_ssdwrap_faults PRIVATE DS4_TESTING)
target_link_libraries(test_g130_ssdwrap_faults PRIVATE
    ds4_cuda
    CUDA::cudart
    CUDA::cublas
)
add_test(NAME test_g130_ssdwrap_faults COMMAND test_g130_ssdwrap_faults)
