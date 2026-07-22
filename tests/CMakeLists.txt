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

if(WIN32)
    add_test(
        NAME g134_specdec_static
        COMMAND powershell.exe -NoProfile -ExecutionPolicy Bypass
                -File ${CMAKE_CURRENT_SOURCE_DIR}/test_g134_specdec_static.ps1
    )
endif()
