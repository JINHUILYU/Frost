cmake_minimum_required(VERSION 3.22)
project(FrostBar LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(FROSTBAR_BUILD_TESTS "Build tests" ON)

add_library(frostbar_core
    core-cpp/src/LayoutEngine.cpp
    core-cpp/src/PolicyEngine.cpp
)

target_include_directories(frostbar_core
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/core-cpp/include
)

target_compile_options(frostbar_core
    PRIVATE
        -Wall
        -Wextra
        -Wpedantic
)

if(FROSTBAR_BUILD_TESTS)
    enable_testing()
    add_executable(core_smoke_test tests/core_smoke_test.cpp)
    target_link_libraries(core_smoke_test PRIVATE frostbar_core)
    add_test(NAME core_smoke_test COMMAND core_smoke_test)
endif()
