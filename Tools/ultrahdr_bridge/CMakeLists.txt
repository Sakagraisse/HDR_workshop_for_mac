cmake_minimum_required(VERSION 3.20)
project(ultrahdr_bridge LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(UHDR_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(UHDR_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(UHDR_BUILD_BENCHMARK OFF CACHE BOOL "" FORCE)
set(UHDR_BUILD_DEPS OFF CACHE BOOL "" FORCE)
set(UHDR_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(UHDR_WRITE_ISO ON CACHE BOOL "" FORCE)
set(UHDR_WRITE_XMP ON CACHE BOOL "" FORCE)

add_subdirectory(
    "${CMAKE_CURRENT_SOURCE_DIR}/../../Vendor/Sources/libultrahdr"
    "${CMAKE_CURRENT_BINARY_DIR}/libultrahdr"
)

add_executable(ultrahdr_bridge main.mm)
target_include_directories(
    ultrahdr_bridge
    PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../../Vendor/Sources/libultrahdr"
)
target_compile_options(ultrahdr_bridge PRIVATE -fobjc-arc)
target_link_libraries(
    ultrahdr_bridge
    PRIVATE
        uhdr
        "-framework Foundation"
        "-framework CoreImage"
        "-framework CoreGraphics"
        "-framework ImageIO"
        "-framework UniformTypeIdentifiers"
)
