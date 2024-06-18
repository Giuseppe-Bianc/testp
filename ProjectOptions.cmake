include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(testp_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(testp_setup_options)
  option(testp_ENABLE_HARDENING "Enable hardening" ON)
  option(testp_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    testp_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    testp_ENABLE_HARDENING
    OFF)

  testp_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR testp_PACKAGING_MAINTAINER_MODE)
    option(testp_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(testp_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(testp_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(testp_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(testp_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(testp_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(testp_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(testp_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(testp_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(testp_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(testp_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(testp_ENABLE_PCH "Enable precompiled headers" OFF)
    option(testp_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(testp_ENABLE_IPO "Enable IPO/LTO" ON)
    option(testp_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(testp_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(testp_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(testp_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(testp_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(testp_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(testp_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(testp_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(testp_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(testp_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(testp_ENABLE_PCH "Enable precompiled headers" OFF)
    option(testp_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      testp_ENABLE_IPO
      testp_WARNINGS_AS_ERRORS
      testp_ENABLE_USER_LINKER
      testp_ENABLE_SANITIZER_ADDRESS
      testp_ENABLE_SANITIZER_LEAK
      testp_ENABLE_SANITIZER_UNDEFINED
      testp_ENABLE_SANITIZER_THREAD
      testp_ENABLE_SANITIZER_MEMORY
      testp_ENABLE_UNITY_BUILD
      testp_ENABLE_CLANG_TIDY
      testp_ENABLE_CPPCHECK
      testp_ENABLE_COVERAGE
      testp_ENABLE_PCH
      testp_ENABLE_CACHE)
  endif()

  testp_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (testp_ENABLE_SANITIZER_ADDRESS OR testp_ENABLE_SANITIZER_THREAD OR testp_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(testp_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(testp_global_options)
  if(testp_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    testp_enable_ipo()
  endif()

  testp_supports_sanitizers()

  if(testp_ENABLE_HARDENING AND testp_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR testp_ENABLE_SANITIZER_UNDEFINED
       OR testp_ENABLE_SANITIZER_ADDRESS
       OR testp_ENABLE_SANITIZER_THREAD
       OR testp_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${testp_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${testp_ENABLE_SANITIZER_UNDEFINED}")
    testp_enable_hardening(testp_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(testp_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(testp_warnings INTERFACE)
  add_library(testp_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  testp_set_project_warnings(
    testp_warnings
    ${testp_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(testp_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    testp_configure_linker(testp_options)
  endif()

  include(cmake/Sanitizers.cmake)
  testp_enable_sanitizers(
    testp_options
    ${testp_ENABLE_SANITIZER_ADDRESS}
    ${testp_ENABLE_SANITIZER_LEAK}
    ${testp_ENABLE_SANITIZER_UNDEFINED}
    ${testp_ENABLE_SANITIZER_THREAD}
    ${testp_ENABLE_SANITIZER_MEMORY})

  set_target_properties(testp_options PROPERTIES UNITY_BUILD ${testp_ENABLE_UNITY_BUILD})

  if(testp_ENABLE_PCH)
    target_precompile_headers(
      testp_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(testp_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    testp_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(testp_ENABLE_CLANG_TIDY)
    testp_enable_clang_tidy(testp_options ${testp_WARNINGS_AS_ERRORS})
  endif()

  if(testp_ENABLE_CPPCHECK)
    testp_enable_cppcheck(${testp_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(testp_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    testp_enable_coverage(testp_options)
  endif()

  if(testp_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(testp_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(testp_ENABLE_HARDENING AND NOT testp_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR testp_ENABLE_SANITIZER_UNDEFINED
       OR testp_ENABLE_SANITIZER_ADDRESS
       OR testp_ENABLE_SANITIZER_THREAD
       OR testp_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    testp_enable_hardening(testp_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
