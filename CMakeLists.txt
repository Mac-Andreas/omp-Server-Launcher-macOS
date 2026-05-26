cmake_minimum_required(VERSION 3.16)

project(ServerLauncher VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Qt6 preferred, Qt5 still works.
find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core Widgets Network)
find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core Widgets Network)

set(SOURCES
  src/main.cpp
  src/LauncherWindow.cpp
  src/CrossOver.cpp
  src/Updater.cpp
  src/LicenseInfo.cpp
  src/TelemetryManager.cpp
  src/ToggleSwitch.cpp
)
set(HEADERS
  src/LauncherWindow.h
  src/CrossOver.h
  src/Updater.h
  src/AppInfo.h
  src/SymbolIcon.h
  src/LicenseInfo.h
  src/TelemetryManager.h
)

if(APPLE)
  # SF Symbols bridge (Objective-C++).
  list(APPEND SOURCES src/SymbolIcon.mm)
endif()

if(APPLE)
  # Build a .icns from the staged PNGs.
  set(ICON_SRC "${CMAKE_CURRENT_SOURCE_DIR}/assets")
  set(ICONSET_DIR "${CMAKE_CURRENT_BINARY_DIR}/launcher.iconset")
  set(ICNS_FILE "${CMAKE_CURRENT_BINARY_DIR}/launcher.icns")
  add_custom_command(
    OUTPUT ${ICNS_FILE}
    COMMAND ${CMAKE_COMMAND} -E make_directory "${ICONSET_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy "${ICON_SRC}/icon_16x16.png"     "${ICONSET_DIR}/icon_16x16.png"
    COMMAND ${CMAKE_COMMAND} -E copy "${ICON_SRC}/icon_32x32.png"     "${ICONSET_DIR}/icon_16x16@2x.png"
    COMMAND ${CMAKE_COMMAND} -E copy "${ICON_SRC}/icon_32x32.png"     "${ICONSET_DIR}/icon_32x32.png"
    COMMAND ${CMAKE_COMMAND} -E copy "${ICON_SRC}/icon_128x128.png"   "${ICONSET_DIR}/icon_128x128.png"
    COMMAND ${CMAKE_COMMAND} -E copy "${ICON_SRC}/icon_256x256.png"   "${ICONSET_DIR}/icon_128x128@2x.png"
    COMMAND ${CMAKE_COMMAND} -E copy "${ICON_SRC}/icon_256x256.png"   "${ICONSET_DIR}/icon_256x256.png"
    COMMAND ${CMAKE_COMMAND} -E copy "${ICON_SRC}/icon_512x512.png"   "${ICONSET_DIR}/icon_256x256@2x.png"
    COMMAND ${CMAKE_COMMAND} -E copy "${ICON_SRC}/icon_512x512.png"   "${ICONSET_DIR}/icon_512x512.png"
    COMMAND ${CMAKE_COMMAND} -E copy "${ICON_SRC}/icon_1024x1024.png" "${ICONSET_DIR}/icon_512x512@2x.png"
    COMMAND iconutil --convert icns --output "${ICNS_FILE}" "${ICONSET_DIR}"
    DEPENDS
      "${ICON_SRC}/icon_16x16.png" "${ICON_SRC}/icon_32x32.png"
      "${ICON_SRC}/icon_128x128.png" "${ICON_SRC}/icon_256x256.png"
      "${ICON_SRC}/icon_512x512.png" "${ICON_SRC}/icon_1024x1024.png"
    COMMENT "Generating launcher.icns"
    VERBATIM
  )
endif()

add_executable(ServerLauncher MACOSX_BUNDLE
  ${SOURCES}
  ${HEADERS}
  launcher.qrc
  ${ICNS_FILE}
)

target_link_libraries(ServerLauncher
  Qt${QT_VERSION_MAJOR}::Core
  Qt${QT_VERSION_MAJOR}::Widgets
  Qt${QT_VERSION_MAJOR}::Network
)

if(APPLE)
  target_link_libraries(ServerLauncher "-framework AppKit")
  # ARC for the Objective-C++ bridge.
  set_source_files_properties(src/SymbolIcon.mm PROPERTIES
    COMPILE_FLAGS "-fobjc-arc")
endif()

if(APPLE)
  set_target_properties(ServerLauncher PROPERTIES
    MACOSX_BUNDLE TRUE
    OUTPUT_NAME "open.mp Server Launcher"
    MACOSX_BUNDLE_BUNDLE_NAME "open.mp Server Launcher"
    MACOSX_BUNDLE_GUI_IDENTIFIER "io.openmultiplayer.serverlauncher"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_ICON_FILE "launcher.icns"
    RESOURCE "${ICNS_FILE}"
  )

  # Ship the Wine wrapper inside the bundle, beside the executable, and the
  # license into Resources (the License tab reads it from there).
  add_custom_command(TARGET ServerLauncher POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
      "${CMAKE_CURRENT_SOURCE_DIR}/scripts/run-omp-server-wine.sh"
      "$<TARGET_FILE_DIR:ServerLauncher>/run-omp-server-wine.sh"
    COMMAND ${CMAKE_COMMAND} -E copy
      "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE.txt"
      "$<TARGET_BUNDLE_DIR:ServerLauncher>/Contents/Resources/LICENSE.txt"
    COMMENT "Bundling wrapper + license"
  )
endif()
