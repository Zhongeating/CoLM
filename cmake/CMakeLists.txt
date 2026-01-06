# ============================================================================
# CoLM CMake Build System
# Supports parallel compilation and conditional compilation based on options
# ============================================================================

cmake_minimum_required(VERSION 3.16)
project(CoLM Fortran)

# ============================================================================
# Build Options (corresponding to include/define.h)
# ============================================================================

# 1. Spatial structure options (select one)
set(SPATIAL_TYPE "GRIDBASED" CACHE STRING "Spatial structure type")
set_property(CACHE SPATIAL_TYPE PROPERTY STRINGS "GRIDBASED" "CATCHMENT" "UNSTRUCTURED" "SinglePoint")

# 2. Land subgrid type classification (select one)
set(LULC_TYPE "LULC_IGBP" CACHE STRING "Land use/land cover classification")
set_property(CACHE LULC_TYPE PROPERTY STRINGS "LULC_USGS" "LULC_IGBP" "LULC_IGBP_PFT" "LULC_IGBP_PC")

# 3. Optional features
option(ENABLE_URBAN_MODEL "Enable 3D Urban model" OFF)
option(ENABLE_BGC "Enable BGC model" OFF)
option(ENABLE_CROP "Enable CROP model" OFF)
option(ENABLE_LULCC "Enable Land use and land cover change" OFF)
option(ENABLE_DATA_ASSIMILATION "Enable Data Assimilation" OFF)
option(ENABLE_MPI "Enable MPI parallelization" ON)
option(ENABLE_CAMA_FLOOD "Enable CaMa-Flood model" OFF)
option(ENABLE_CATCH_LATERAL_FLOW "Enable Catchment lateral flow" OFF)
option(ENABLE_GRID_RIVER_LAKE_FLOW "Enable Grid river lake flow" OFF)

# 4. Debug options
option(ENABLE_DEBUG "Enable debug information output" OFF)
option(ENABLE_RANGE_CHECK "Enable range checking of variables" OFF)
option(ENABLE_SRFDATA_DIAG "Enable surface data diagnostics" OFF)

# 5. Soil hydraulic model (select one)
set(SOIL_MODEL "Campbell" CACHE STRING "Soil hydraulic model")
set_property(CACHE SOIL_MODEL PROPERTY STRINGS "Campbell" "vanGenuchten_Mualem")

# ============================================================================
# Handle option conflicts and dependencies
# ============================================================================

# SinglePoint conflicts with MPI
if(SPATIAL_TYPE STREQUAL "SinglePoint")
    set(ENABLE_MPI OFF CACHE BOOL "MPI disabled for SinglePoint" FORCE)
    set(ENABLE_CAMA_FLOOD OFF CACHE BOOL "CaMa-Flood disabled for SinglePoint" FORCE)
endif()

# CaMa-Flood requires MPI
if(ENABLE_CAMA_FLOOD AND NOT ENABLE_MPI)
    message(WARNING "CaMa-Flood requires MPI. Disabling CaMa-Flood.")
    set(ENABLE_CAMA_FLOOD OFF CACHE BOOL "CaMa-Flood disabled" FORCE)
endif()

# Catchment lateral flow only for CATCHMENT spatial type
if(NOT SPATIAL_TYPE STREQUAL "CATCHMENT")
    set(ENABLE_CATCH_LATERAL_FLOW OFF CACHE BOOL "Catchment lateral flow disabled" FORCE)
endif()

# Grid river lake flow conflicts
if(SPATIAL_TYPE STREQUAL "CATCHMENT" OR SPATIAL_TYPE STREQUAL "SinglePoint")
    set(ENABLE_GRID_RIVER_LAKE_FLOW OFF CACHE BOOL "Grid river lake flow disabled" FORCE)
endif()

# BGC requires LULC_IGBP_PFT or LULC_IGBP_PC
if(ENABLE_BGC AND NOT (LULC_TYPE STREQUAL "LULC_IGBP_PFT" OR LULC_TYPE STREQUAL "LULC_IGBP_PC"))
    message(WARNING "BGC requires LULC_IGBP_PFT or LULC_IGBP_PC. Disabling BGC.")
    set(ENABLE_BGC OFF CACHE BOOL "BGC disabled" FORCE)
endif()

# CROP requires BGC
if(ENABLE_CROP AND NOT ENABLE_BGC)
    message(WARNING "CROP requires BGC. Disabling CROP.")
    set(ENABLE_CROP OFF CACHE BOOL "CROP disabled" FORCE)
endif()

# Data Assimilation forces LULC_IGBP
if(ENABLE_DATA_ASSIMILATION)
    set(LULC_TYPE "LULC_IGBP" CACHE STRING "LULC type forced to IGBP for DA" FORCE)
endif()

# Urban model with SinglePoint forces LULC_IGBP
if(ENABLE_URBAN_MODEL AND SPATIAL_TYPE STREQUAL "SinglePoint")
    set(LULC_TYPE "LULC_IGBP" CACHE STRING "LULC type forced to IGBP for Urban SinglePoint" FORCE)
endif()

# ============================================================================
# Find required packages
# ============================================================================

# Find NetCDF
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(NETCDF_F QUIET netcdf-fortran)
endif()

if(NOT NETCDF_F_FOUND)
    # Manual NetCDF configuration
    set(NETCDF_LIB "/usr/local/lib" CACHE PATH "NetCDF library path")
    set(NETCDF_INC "/usr/local/include" CACHE PATH "NetCDF include path")
    set(NETCDF_LIBRARIES "-L${NETCDF_LIB} -lnetcdff -lnetcdf")
    set(NETCDF_INCLUDE_DIRS "${NETCDF_INC}")
else()
    set(NETCDF_LIBRARIES ${NETCDF_F_LDFLAGS})
    set(NETCDF_INCLUDE_DIRS ${NETCDF_F_INCLUDE_DIRS})
endif()

# Find MPI if enabled
if(ENABLE_MPI)
    find_package(MPI REQUIRED)
    set(CMAKE_Fortran_COMPILER ${MPI_Fortran_COMPILER})
endif()

# Find LAPACK and BLAS
find_package(LAPACK QUIET)
if(NOT LAPACK_FOUND)
    set(LAPACK_LIBRARIES "-llapack -lblas")
endif()

# ============================================================================
# Compiler flags
# ============================================================================

# Detect compiler - need to handle MPI wrappers
get_filename_component(Fortran_COMPILER_NAME ${CMAKE_Fortran_COMPILER} NAME)

# For MPI wrappers, try to detect the underlying compiler
set(UNDERLYING_COMPILER "")
if(Fortran_COMPILER_NAME MATCHES "mpifort.*" OR Fortran_COMPILER_NAME MATCHES "mpif90.*")
    # Try to get the underlying compiler from mpifort
    execute_process(
        COMMAND ${CMAKE_Fortran_COMPILER} -show
        OUTPUT_VARIABLE MPI_SHOW_OUTPUT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(MPI_SHOW_OUTPUT)
        # Extract the first word (compiler name)
        string(REGEX MATCH "^[^ ]+" UNDERLYING_COMPILER "${MPI_SHOW_OUTPUT}")
        get_filename_component(UNDERLYING_COMPILER "${UNDERLYING_COMPILER}" NAME)
        message(STATUS "Detected underlying compiler from MPI wrapper: ${UNDERLYING_COMPILER}")
    endif()
endif()

# Use underlying compiler if detected, otherwise use the compiler name directly
if(UNDERLYING_COMPILER)
    set(COMPILER_TO_CHECK "${UNDERLYING_COMPILER}")
else()
    set(COMPILER_TO_CHECK "${Fortran_COMPILER_NAME}")
endif()

# Also check CMAKE_Fortran_COMPILER_ID which CMake sets
message(STATUS "Fortran compiler: ${CMAKE_Fortran_COMPILER}")
message(STATUS "Fortran compiler name: ${Fortran_COMPILER_NAME}")
message(STATUS "Fortran compiler ID: ${CMAKE_Fortran_COMPILER_ID}")
message(STATUS "Compiler to check: ${COMPILER_TO_CHECK}")

# Set compiler flags based on detected compiler
if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU" OR COMPILER_TO_CHECK MATCHES "gfortran.*")
    message(STATUS "Using GNU Fortran compiler flags")
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -cpp -ffree-form -fimplicit-none")
    set(CMAKE_Fortran_FLAGS_DEBUG "-g -Wall -fbounds-check -fbacktrace")
    set(CMAKE_Fortran_FLAGS_RELEASE "-O3")
    set(FORTRAN_REAL8_FLAG "-fdefault-real-8")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel" OR COMPILER_TO_CHECK MATCHES "ifort.*" OR COMPILER_TO_CHECK MATCHES "ifx.*")
    message(STATUS "Using Intel Fortran compiler flags")
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -cpp -free")
    set(CMAKE_Fortran_FLAGS_DEBUG "-g -warn all -check bounds -traceback")
    set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
    set(FORTRAN_REAL8_FLAG "-r8")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "PGI" OR CMAKE_Fortran_COMPILER_ID MATCHES "NVHPC" OR 
       COMPILER_TO_CHECK MATCHES "pgfortran.*" OR COMPILER_TO_CHECK MATCHES "nvfortran.*" OR
       Fortran_COMPILER_NAME MATCHES "pgfortran.*" OR Fortran_COMPILER_NAME MATCHES "nvfortran.*")
    message(STATUS "Using NVIDIA/PGI Fortran compiler flags")
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Mfreeform -Mpreprocess")
    set(CMAKE_Fortran_FLAGS_DEBUG "-g -traceback")
    set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
    set(FORTRAN_REAL8_FLAG "-r8")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Flang")
    message(STATUS "Using Flang compiler flags")
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Mfreeform -Mpreprocess")
    set(CMAKE_Fortran_FLAGS_DEBUG "-g")
    set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
    set(FORTRAN_REAL8_FLAG "-r8")
else()
    message(STATUS "Using default Fortran compiler flags (assuming GNU-compatible)")
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -cpp -ffree-form")
    set(CMAKE_Fortran_FLAGS_DEBUG "-g")
    set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
    set(FORTRAN_REAL8_FLAG "-fdefault-real-8")
endif()

set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} ${FORTRAN_REAL8_FLAG}")

# ============================================================================
# Preprocessor definitions
# ============================================================================

# NOTE: We do NOT pass preprocessor definitions via -D flags because
# the source files already include "define.h" which contains all the
# necessary macro definitions. Passing them via -D would cause
# "Redefinition of symbol" warnings with NVIDIA/PGI compilers.
#
# The configuration in include/define.h should match the CMake options.
# Users should edit include/define.h to match their desired configuration.

set(COLM_DEFINITIONS "")

# Only add definitions that are NOT in define.h or need to override
# (Currently empty - all definitions come from define.h)

# ============================================================================
# Include directories
# ============================================================================

set(COLM_INCLUDE_DIRS
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_BINARY_DIR}/modules
    ${NETCDF_INCLUDE_DIRS}
)

# Create module output directory
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/modules)

# Set module output directory
set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/modules)

# ============================================================================
# Source files - Shared modules (Level 0-5)
# ============================================================================

set(SOURCES_SHARED_L0
    share/MOD_Precision.F90
    share/MOD_IncompleteGamma.F90
)

set(SOURCES_SHARED_L1
    share/MOD_SPMD_Task.F90
    share/MOD_Namelist.F90
    share/MOD_UserDefFun.F90
    main/MOD_Const_Physical.F90
)

set(SOURCES_SHARED_L2
    main/MOD_Vars_Global.F90
    share/MOD_Utils.F90
    share/MOD_TimeManager.F90
    main/MOD_Const_LC.F90
)

set(SOURCES_SHARED_L3
    share/MOD_NetCDFSerial.F90
    share/MOD_Block.F90
    share/MOD_Grid.F90
    share/MOD_Pixel.F90
    share/MOD_DataType.F90
)

set(SOURCES_SHARED_L4
    share/MOD_NetCDFPoint.F90
    share/MOD_NetCDFBlock.F90
    share/MOD_CatchmentDataReadin.F90
    share/MOD_5x5DataReadin.F90
    share/MOD_Mesh.F90
    share/MOD_Pixelset.F90
    share/MOD_NetCDFVector.F90
    share/MOD_RangeCheck.F90
    share/MOD_SpatialMapping.F90
)

set(SOURCES_SHARED_L5
    share/MOD_WorkerPushData.F90
    mksrfdata/MOD_AggregationRequestData.F90
    mksrfdata/MOD_PixelsetShared.F90
    mksrfdata/MOD_LandElm.F90
    mksrfdata/MOD_LandPatch.F90
    mksrfdata/MOD_Land2mWMO.F90
    mksrfdata/MOD_LandUrban.F90
    main/URBAN/MOD_Urban_Const_LCZ.F90
    mksrfdata/MOD_SrfdataRestart.F90
    mksrfdata/MOD_MeshFilter.F90
    mksrfdata/MOD_RegionClip.F90
)

# Conditional source files based on preprocessor macros in define.h
# These files become empty after preprocessing in certain modes,
# which causes compilation errors with some compilers (e.g., NVIDIA/PGI)

# MOD_LandHRU.F90 only compiles for CATCHMENT
if(SPATIAL_TYPE STREQUAL "CATCHMENT")
    list(APPEND SOURCES_SHARED_L5 mksrfdata/MOD_LandHRU.F90)
endif()

# MOD_ElmVector.F90 only compiles for UNSTRUCTURED or CATCHMENT
# MOD_HRUVector.F90 only compiles for CATCHMENT
if(SPATIAL_TYPE STREQUAL "CATCHMENT" OR SPATIAL_TYPE STREQUAL "UNSTRUCTURED")
    list(APPEND SOURCES_SHARED_L5 mksrfdata/MOD_ElmVector.F90)
endif()
if(SPATIAL_TYPE STREQUAL "CATCHMENT")
    list(APPEND SOURCES_SHARED_L5 mksrfdata/MOD_HRUVector.F90)
endif()

# MOD_LandPFT.F90 only compiles for LULC_IGBP_PFT or LULC_IGBP_PC
if(LULC_TYPE STREQUAL "LULC_IGBP_PFT" OR LULC_TYPE STREQUAL "LULC_IGBP_PC")
    list(APPEND SOURCES_SHARED_L5 mksrfdata/MOD_LandPFT.F90)
endif()

# MOD_LandCrop.F90 only compiles for CROP (which requires BGC)
if(ENABLE_CROP)
    list(APPEND SOURCES_SHARED_L5 mksrfdata/MOD_LandCrop.F90)
endif()

# MOD_SingleSrfdata.F90 only compiles for SinglePoint
if(SPATIAL_TYPE STREQUAL "SinglePoint")
    list(APPEND SOURCES_SHARED_L5 mksrfdata/MOD_SingleSrfdata.F90)
endif()

# MOD_SrfdataDiag.F90 only compiles when SrfdataDiag is enabled
if(ENABLE_SRFDATA_DIAG)
    list(APPEND SOURCES_SHARED_L5 mksrfdata/MOD_SrfdataDiag.F90)
endif()

set(SOURCES_SHARED
    ${SOURCES_SHARED_L0}
    ${SOURCES_SHARED_L1}
    ${SOURCES_SHARED_L2}
    ${SOURCES_SHARED_L3}
    ${SOURCES_SHARED_L4}
    ${SOURCES_SHARED_L5}
)

# ============================================================================
# Source files - MKSRFDATA
# ============================================================================

set(SOURCES_MKSRFDATA
    mksrfdata/Aggregation_PercentagesPFT.F90
    mksrfdata/Aggregation_LAI.F90
    mksrfdata/Aggregation_SoilBrightness.F90
    mksrfdata/Aggregation_LakeDepth.F90
    mksrfdata/Aggregation_ForestHeight.F90
    mksrfdata/Aggregation_SoilParameters.F90
    mksrfdata/Aggregation_DBedrock.F90
    mksrfdata/Aggregation_Topography.F90
    mksrfdata/Aggregation_TopoWetness.F90
    mksrfdata/Aggregation_TopographyFactors.F90
    mksrfdata/Aggregation_TopographyFactors_Simple.F90
    mksrfdata/Aggregation_Urban.F90
    mksrfdata/Aggregation_SoilTexture.F90
    mksrfdata/MOD_Lulcc_TransferTrace.F90
    mksrfdata/MKSRFDATA.F90
)

# ============================================================================
# Source files - BASIC modules
# ============================================================================

set(SOURCES_BASIC_CORE
    main/HYDRO/MOD_Vector_ReadWrite.F90
    main/MOD_Const_PFT.F90
    main/MOD_Vars_1DForcing.F90
    main/MOD_Vars_2DForcing.F90
)

# MOD_Vars_1DPFTFluxes.F90 only compiles for LULC_IGBP_PFT or LULC_IGBP_PC
if(LULC_TYPE STREQUAL "LULC_IGBP_PFT" OR LULC_TYPE STREQUAL "LULC_IGBP_PC")
    list(APPEND SOURCES_BASIC_CORE main/MOD_Vars_1DPFTFluxes.F90)
endif()

# BGC basic modules - only compile when BGC is enabled
# These files become empty after preprocessing when BGC is disabled
if(ENABLE_BGC)
    set(SOURCES_BASIC_BGC
        main/BGC/MOD_BGC_Vars_1DFluxes.F90
        main/BGC/MOD_BGC_Vars_1DPFTFluxes.F90
        main/BGC/MOD_BGC_Vars_PFTimeVariables.F90
        main/BGC/MOD_BGC_Vars_TimeInvariants.F90
        main/BGC/MOD_BGC_Vars_TimeVariables.F90
    )
else()
    set(SOURCES_BASIC_BGC "")
endif()

# Urban basic modules - only compile when URBAN_MODEL is enabled
# These files become empty after preprocessing when URBAN_MODEL is disabled
if(ENABLE_URBAN_MODEL)
    set(SOURCES_BASIC_URBAN
        main/URBAN/MOD_Urban_Vars_1DFluxes.F90
        main/URBAN/MOD_Urban_Vars_TimeVariables.F90
        main/URBAN/MOD_Urban_Vars_TimeInvariants.F90
    )
else()
    set(SOURCES_BASIC_URBAN "")
endif()

# DA basic modules - only compile when DataAssimilation is enabled
# These files become empty after preprocessing when DataAssimilation is disabled
if(ENABLE_DATA_ASSIMILATION)
    set(SOURCES_BASIC_DA
        main/DA/MOD_DA_Vars_1DFluxes.F90
        main/DA/MOD_DA_Vars_TimeVariables.F90
    )
else()
    set(SOURCES_BASIC_DA "")
endif()

# Catchment modules - only compile when CATCHMENT spatial type is selected
if(SPATIAL_TYPE STREQUAL "CATCHMENT")
    set(SOURCES_BASIC_CATCH
        main/HYDRO/MOD_Catch_BasinNetwork.F90
        main/HYDRO/MOD_Catch_Vars_TimeVariables.F90
        main/HYDRO/MOD_Catch_Vars_1DFluxes.F90
    )
else()
    set(SOURCES_BASIC_CATCH "")
endif()

# Grid river modules (conditional)
set(SOURCES_BASIC_RIVER "")
if(NOT SPATIAL_TYPE STREQUAL "SinglePoint")
    set(SOURCES_BASIC_RIVER
        main/HYDRO/MOD_Grid_RiverLakeNetwork.F90
        main/HYDRO/MOD_Grid_Reservoir.F90
        main/HYDRO/MOD_Grid_RiverLakeTimeVars.F90
    )
endif()

# Extended basic modules
set(SOURCES_BASIC_EXT
    main/MOD_Vars_TimeInvariants.F90
    main/MOD_Vars_TimeVariables.F90
    main/MOD_Vars_1DFluxes.F90
    main/HYDRO/MOD_Hydro_SoilFunction.F90
    main/HYDRO/MOD_Hydro_SoilWater.F90
    main/MOD_Eroot.F90
    main/MOD_Qsadv.F90
    main/MOD_LAIEmpirical.F90
    main/MOD_LAIReadin.F90
    main/MOD_OrbCoszen.F90
    main/MOD_OrbCosazi.F90
    main/MOD_3DCanopyRadiation.F90
    main/MOD_Aerosol.F90
    main/MOD_SnowSnicar.F90
    main/MOD_Albedo.F90
    main/MOD_SnowFraction.F90
    main/MOD_MonthlyinSituCO2MaunaLoa.F90
)

# Data reading modules
set(SOURCES_BASIC_IO
    mkinidata/MOD_PercentagesPFTReadin.F90
    mkinidata/MOD_LakeDepthReadin.F90
    mkinidata/MOD_DBedrockReadin.F90
    mkinidata/MOD_SoilColorRefl.F90
    mkinidata/MOD_SoilParametersReadin.F90
    mkinidata/MOD_SoilTextureReadin.F90
    mkinidata/MOD_HtopReadin.F90
    main/MOD_CropReadin.F90
    main/MOD_NitrifData.F90
    main/MOD_NdepData.F90
    main/MOD_FireData.F90
)

# Urban reading modules (conditional)
if(ENABLE_URBAN_MODEL)
    list(APPEND SOURCES_BASIC_IO
        main/URBAN/MOD_Urban_LAIReadin.F90
        main/URBAN/MOD_Urban_Shortwave.F90
        main/URBAN/MOD_Urban_Albedo.F90
        mkinidata/MOD_UrbanReadin.F90
    )
endif()

# BGC summary (conditional)
if(ENABLE_BGC)
    list(APPEND SOURCES_BASIC_IO main/BGC/MOD_BGC_CNSummary.F90)
endif()

# Initialization modules
set(SOURCES_BASIC_INIT
    mkinidata/MOD_IniTimeVariable.F90
    mkinidata/MOD_UrbanIniTimeVariable.F90
    main/HYDRO/MOD_ElementNeighbour.F90
    main/MOD_VicParaReadin.F90
    mkinidata/MOD_Initialize.F90
)

# Catchment network modules (conditional)
if(SPATIAL_TYPE STREQUAL "CATCHMENT")
    list(APPEND SOURCES_BASIC_INIT
        main/HYDRO/MOD_Catch_HillslopeNetwork.F90
        main/HYDRO/MOD_Catch_RiverLakeNetwork.F90
        main/HYDRO/MOD_Catch_Reservoir.F90
    )
endif()

set(SOURCES_BASIC
    ${SOURCES_BASIC_CORE}
    ${SOURCES_BASIC_BGC}
    ${SOURCES_BASIC_URBAN}
    ${SOURCES_BASIC_DA}
    ${SOURCES_BASIC_CATCH}
    ${SOURCES_BASIC_RIVER}
    ${SOURCES_BASIC_EXT}
    ${SOURCES_BASIC_IO}
    ${SOURCES_BASIC_INIT}
)

# ============================================================================
# Source files - MKINIDATA
# ============================================================================

set(SOURCES_MKINIDATA
    mkinidata/CoLMINI.F90
)

# ============================================================================
# Source files - CaMa-Flood (conditional)
# ============================================================================

set(SOURCES_CAMA "")
if(ENABLE_CAMA_FLOOD)
    set(SOURCES_CAMA
        extends/CaMa/src/parkind1.F90
        extends/CaMa/src/yos_cmf_input.F90
        extends/CaMa/src/yos_cmf_time.F90
        extends/CaMa/src/yos_cmf_map.F90
        extends/CaMa/src/yos_cmf_prog.F90
        extends/CaMa/src/yos_cmf_diag.F90
        extends/CaMa/src/cmf_utils_mod.F90
        extends/CaMa/src/cmf_calc_outflw_mod.F90
        extends/CaMa/src/cmf_calc_pthout_mod.F90
        extends/CaMa/src/cmf_calc_fldstg_mod.F90
        extends/CaMa/src/cmf_calc_stonxt_mod.F90
        extends/CaMa/src/cmf_opt_outflw_mod.F90
        extends/CaMa/src/cmf_ctrl_tracer_mod.F90
        extends/CaMa/src/cmf_ctrl_mpi_mod.F90
        extends/CaMa/src/cmf_ctrl_damout_mod.F90
        extends/CaMa/src/cmf_ctrl_levee_mod.F90
        extends/CaMa/src/cmf_ctrl_forcing_mod.F90
        extends/CaMa/src/cmf_ctrl_boundary_mod.F90
        extends/CaMa/src/cmf_ctrl_output_mod.F90
        extends/CaMa/src/cmf_ctrl_restart_mod.F90
        extends/CaMa/src/cmf_ctrl_sed_mod.F90
        extends/CaMa/src/cmf_calc_diag_mod.F90
        extends/CaMa/src/cmf_ctrl_physics_mod.F90
        extends/CaMa/src/cmf_ctrl_time_mod.F90
        extends/CaMa/src/cmf_ctrl_maps_mod.F90
        extends/CaMa/src/cmf_ctrl_vars_mod.F90
        extends/CaMa/src/cmf_ctrl_nmlist_mod.F90
        extends/CaMa/src/cmf_drv_control_mod.F90
        extends/CaMa/src/cmf_drv_advance_mod.F90
    )
endif()

# ============================================================================
# Source files - MAIN physics modules
# ============================================================================

set(SOURCES_PHYSICS
    main/MOD_AssimStomataConductance.F90
    main/MOD_PlantHydraulic.F90
    main/MOD_FrictionVelocity.F90
    main/MOD_TurbulenceLEddy.F90
    main/MOD_Ozone.F90
    main/MOD_CanopyLayerProfile.F90
    main/MOD_LeafTemperature.F90
    main/MOD_LeafTemperaturePC.F90
    main/MOD_SoilThermalParameters.F90
    main/MOD_Runoff.F90
    main/MOD_SoilSnowHydrology.F90
    main/MOD_SnowLayersCombineDivide.F90
    main/MOD_PhaseChange.F90
    main/MOD_Glacier.F90
    main/MOD_Lake.F90
    main/MOD_SimpleOcean.F90
    main/MOD_GroundFluxes.F90
    main/MOD_GroundTemperature.F90
    main/MOD_LeafInterception.F90
    main/MOD_NetSolar.F90
    main/MOD_WetBulb.F90
    main/MOD_RainSnowTemp.F90
    main/MOD_SoilSurfaceResistance.F90
    main/MOD_NewSnow.F90
    main/MOD_Thermal.F90
    main/HYDRO/MOD_Hydro_VIC_Variables.F90
    main/HYDRO/MOD_Hydro_VIC.F90
)

# Catchment hydrology modules (conditional)
set(SOURCES_HYDRO "")
if(SPATIAL_TYPE STREQUAL "CATCHMENT")
    set(SOURCES_HYDRO
        main/HYDRO/MOD_Catch_HillslopeFlow.F90
        main/HYDRO/MOD_Catch_SubsurfaceFlow.F90
        main/HYDRO/MOD_Catch_RiverLakeFlow.F90
        main/HYDRO/MOD_Catch_Hist.F90
        main/HYDRO/MOD_Catch_WriteParameters.F90
    )
endif()

# Grid river modules (conditional)
set(SOURCES_GRID_RIVER "")
if(NOT SPATIAL_TYPE STREQUAL "SinglePoint")
    list(APPEND SOURCES_GRID_RIVER main/HYDRO/MOD_Grid_RiverLakeHist.F90)
    if(ENABLE_GRID_RIVER_LAKE_FLOW)
        list(APPEND SOURCES_GRID_RIVER main/HYDRO/MOD_Grid_RiverLakeFlow.F90)
    endif()
endif()

# BGC modules (conditional)
set(SOURCES_BGC "")
if(ENABLE_BGC)
    set(SOURCES_BGC
        main/BGC/MOD_BGC_CNCStateUpdate1.F90
        main/BGC/MOD_BGC_CNCStateUpdate2.F90
        main/BGC/MOD_BGC_CNCStateUpdate3.F90
        main/BGC/MOD_BGC_CNNStateUpdate1.F90
        main/BGC/MOD_BGC_CNNStateUpdate2.F90
        main/BGC/MOD_BGC_CNNStateUpdate3.F90
        main/BGC/MOD_BGC_Soil_BiogeochemNStateUpdate1.F90
        main/BGC/MOD_BGC_Soil_BiogeochemNitrifDenitrif.F90
        main/BGC/MOD_BGC_Soil_BiogeochemCompetition.F90
        main/BGC/MOD_BGC_Soil_BiogeochemDecompCascadeBGC.F90
        main/BGC/MOD_BGC_Soil_BiogeochemDecomp.F90
        main/BGC/MOD_BGC_Soil_BiogeochemLittVertTransp.F90
        main/BGC/MOD_BGC_Soil_BiogeochemNLeaching.F90
        main/BGC/MOD_BGC_Soil_BiogeochemPotential.F90
        main/BGC/MOD_BGC_Soil_BiogeochemVerticalProfile.F90
        main/BGC/MOD_BGC_Veg_CNGapMortality.F90
        main/BGC/MOD_BGC_Veg_CNGResp.F90
        main/BGC/MOD_BGC_Veg_CNMResp.F90
        main/BGC/MOD_BGC_Daylength.F90
        main/BGC/MOD_BGC_Veg_CNPhenology.F90
        main/BGC/MOD_BGC_Veg_NutrientCompetition.F90
        main/BGC/MOD_BGC_Veg_CNVegStructUpdate.F90
        main/BGC/MOD_BGC_CNAnnualUpdate.F90
        main/BGC/MOD_BGC_CNZeroFluxes.F90
        main/BGC/MOD_BGC_CNBalanceCheck.F90
        main/BGC/MOD_BGC_CNSASU.F90
        main/BGC/MOD_BGC_Veg_CNNDynamics.F90
        main/BGC/MOD_BGC_Veg_CNFireBase.F90
        main/BGC/MOD_BGC_Veg_CNFireLi2016.F90
        main/BGC/MOD_BGC_driver.F90
    )
endif()

# Urban modules (conditional)
set(SOURCES_URBAN "")
if(ENABLE_URBAN_MODEL)
    set(SOURCES_URBAN
        main/URBAN/MOD_Urban_Longwave.F90
        main/URBAN/MOD_Urban_NetSolar.F90
        main/URBAN/MOD_Urban_Flux.F90
        main/URBAN/MOD_Urban_GroundFlux.F90
        main/URBAN/MOD_Urban_RoofFlux.F90
        main/URBAN/MOD_Urban_RoofTemperature.F90
        main/URBAN/MOD_Urban_WallTemperature.F90
        main/URBAN/MOD_Urban_PerviousTemperature.F90
        main/URBAN/MOD_Urban_ImperviousTemperature.F90
        main/URBAN/MOD_Urban_Hydrology.F90
        main/URBAN/MOD_Urban_BEM.F90
        main/URBAN/MOD_Urban_LUCY.F90
        main/URBAN/MOD_Urban_Thermal.F90
        main/URBAN/CoLMMAIN_Urban.F90
    )
endif()

# LULCC modules (conditional)
set(SOURCES_LULCC "")
if(ENABLE_LULCC)
    set(SOURCES_LULCC
        main/LULCC/MOD_Lulcc_Vars_TimeInvariants.F90
        main/LULCC/MOD_Lulcc_Vars_TimeVariables.F90
        main/LULCC/MOD_Lulcc_TransferTraceReadin.F90
        main/LULCC/MOD_Lulcc_MassEnergyConserve.F90
        main/LULCC/MOD_Lulcc_Initialize.F90
        main/LULCC/MOD_Lulcc_Driver.F90
    )
endif()

# DA modules (conditional)
set(SOURCES_DA "")
if(ENABLE_DATA_ASSIMILATION)
    set(SOURCES_DA
        main/DA/MOD_DA_Const.F90
        main/DA/MOD_DA_RTM.F90
        main/DA/MOD_DA_EnKF.F90
        main/DA/MOD_DA_TWS.F90
        main/DA/MOD_DA_SM.F90
        main/DA/MOD_DA_Ensemble.F90
        main/DA/MOD_DA_Main.F90
    )
endif()

# Forcing and output modules
set(SOURCES_IO
    main/MOD_UserSpecifiedForcing.F90
    main/MOD_ForcingDownscaling.F90
    main/MOD_Forcing.F90
    main/MOD_Vars_1DAccFluxes.F90
    main/MOD_Irrigation.F90
    main/MOD_HistWriteBack.F90
    main/MOD_HistGridded.F90
    main/MOD_HistVector.F90
    main/MOD_HistSingle.F90
    main/MOD_Hist.F90
    main/MOD_CheckEquilibrium.F90
    main/MOD_LightningData.F90
)

# CaMa coupling (conditional)
if(ENABLE_CAMA_FLOOD)
    list(APPEND SOURCES_IO
        extends/CaMa/src/MOD_CaMa_Vars.F90
        extends/CaMa/src/MOD_CaMa_colmCaMa.F90
    )
endif()

# Catchment lateral flow (conditional)
set(SOURCES_CATCH_FLOW "")
if(ENABLE_CATCH_LATERAL_FLOW)
    set(SOURCES_CATCH_FLOW main/HYDRO/MOD_Catch_LateralFlow.F90)
endif()

# Main driver modules
set(SOURCES_DRIVER
    main/CoLMMAIN.F90
    main/CoLMDRIVER.F90
    main/CoLM.F90
)

set(SOURCES_MAIN
    ${SOURCES_PHYSICS}
    ${SOURCES_HYDRO}
    ${SOURCES_GRID_RIVER}
    ${SOURCES_BGC}
    ${SOURCES_URBAN}
    ${SOURCES_LULCC}
    ${SOURCES_DA}
    ${SOURCES_IO}
    ${SOURCES_CATCH_FLOW}
    ${SOURCES_DRIVER}
)

# ============================================================================
# Source files - Postprocess
# ============================================================================

set(SOURCES_POST_CONCATENATE
    postprocess/MOD_Concatenate.F90
    postprocess/HistConcatenate.F90
)

set(SOURCES_POST_VECTOR2GRID
    postprocess/MOD_Vector2Grid.F90
    postprocess/POST_Vector2Grid.F90
)

set(SOURCES_POST_SRFDATA
    postprocess/SrfDataConcatenate.F90
)

# ============================================================================
# Create shared library
# ============================================================================

add_library(colm_shared OBJECT ${SOURCES_SHARED})
target_include_directories(colm_shared PRIVATE ${COLM_INCLUDE_DIRS})
target_compile_definitions(colm_shared PRIVATE ${COLM_DEFINITIONS})

# ============================================================================
# Executable: mksrfdata.x
# ============================================================================

add_executable(mksrfdata.x
    ${SOURCES_MKSRFDATA}
    $<TARGET_OBJECTS:colm_shared>
)
target_include_directories(mksrfdata.x PRIVATE ${COLM_INCLUDE_DIRS})
target_compile_definitions(mksrfdata.x PRIVATE ${COLM_DEFINITIONS})
target_link_libraries(mksrfdata.x ${NETCDF_LIBRARIES} ${LAPACK_LIBRARIES})
set_target_properties(mksrfdata.x PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/run
)

# ============================================================================
# Executable: mkinidata.x
# ============================================================================

add_library(colm_basic OBJECT ${SOURCES_BASIC})
target_include_directories(colm_basic PRIVATE ${COLM_INCLUDE_DIRS})
target_compile_definitions(colm_basic PRIVATE ${COLM_DEFINITIONS})
add_dependencies(colm_basic colm_shared)

add_executable(mkinidata.x
    ${SOURCES_MKINIDATA}
    $<TARGET_OBJECTS:colm_shared>
    $<TARGET_OBJECTS:colm_basic>
)
target_include_directories(mkinidata.x PRIVATE ${COLM_INCLUDE_DIRS})
target_compile_definitions(mkinidata.x PRIVATE ${COLM_DEFINITIONS})
target_link_libraries(mkinidata.x ${NETCDF_LIBRARIES} ${LAPACK_LIBRARIES})
set_target_properties(mkinidata.x PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/run
)

# ============================================================================
# Executable: colm.x
# ============================================================================

# CaMa library (conditional)
if(ENABLE_CAMA_FLOOD)
    add_library(cama OBJECT ${SOURCES_CAMA})
    target_include_directories(cama PRIVATE ${COLM_INCLUDE_DIRS})
    target_compile_definitions(cama PRIVATE ${COLM_DEFINITIONS} UseCDF UseCDF_CMF)
endif()

add_executable(colm.x
    ${SOURCES_MAIN}
    $<TARGET_OBJECTS:colm_shared>
    $<TARGET_OBJECTS:colm_basic>
    $<$<BOOL:${ENABLE_CAMA_FLOOD}>:$<TARGET_OBJECTS:cama>>
)
target_include_directories(colm.x PRIVATE ${COLM_INCLUDE_DIRS})
target_compile_definitions(colm.x PRIVATE ${COLM_DEFINITIONS})
target_link_libraries(colm.x ${NETCDF_LIBRARIES} ${LAPACK_LIBRARIES})
set_target_properties(colm.x PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/run
)

# ============================================================================
# Postprocess executables
# ============================================================================

add_executable(hist_concatenate.x
    ${SOURCES_POST_CONCATENATE}
    $<TARGET_OBJECTS:colm_shared>
)
target_include_directories(hist_concatenate.x PRIVATE ${COLM_INCLUDE_DIRS})
target_compile_definitions(hist_concatenate.x PRIVATE ${COLM_DEFINITIONS})
target_link_libraries(hist_concatenate.x ${NETCDF_LIBRARIES} ${LAPACK_LIBRARIES})
set_target_properties(hist_concatenate.x PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/run
)

add_executable(srfdata_concatenate.x
    ${SOURCES_POST_SRFDATA}
    $<TARGET_OBJECTS:colm_shared>
)
target_include_directories(srfdata_concatenate.x PRIVATE ${COLM_INCLUDE_DIRS})
target_compile_definitions(srfdata_concatenate.x PRIVATE ${COLM_DEFINITIONS})
target_link_libraries(srfdata_concatenate.x ${NETCDF_LIBRARIES} ${LAPACK_LIBRARIES})
set_target_properties(srfdata_concatenate.x PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/run
)

# post_vector2grid.x only for non-gridbased
if(NOT SPATIAL_TYPE STREQUAL "GRIDBASED")
    add_executable(post_vector2grid.x
        ${SOURCES_POST_VECTOR2GRID}
        $<TARGET_OBJECTS:colm_shared>
    )
    target_include_directories(post_vector2grid.x PRIVATE ${COLM_INCLUDE_DIRS})
    target_compile_definitions(post_vector2grid.x PRIVATE ${COLM_DEFINITIONS})
    target_link_libraries(post_vector2grid.x ${NETCDF_LIBRARIES} ${LAPACK_LIBRARIES})
    set_target_properties(post_vector2grid.x PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/run
    )
endif()

# ============================================================================
# Static library
# ============================================================================

add_library(colm STATIC
    $<TARGET_OBJECTS:colm_shared>
    $<TARGET_OBJECTS:colm_basic>
)
set_target_properties(colm PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/lib
    OUTPUT_NAME colm
)

# ============================================================================
# Custom targets
# ============================================================================

# Target: all executables
add_custom_target(all_executables
    DEPENDS mksrfdata.x mkinidata.x colm.x hist_concatenate.x srfdata_concatenate.x
)

# Target: postprocess
add_custom_target(postprocess
    DEPENDS hist_concatenate.x srfdata_concatenate.x
)
if(NOT SPATIAL_TYPE STREQUAL "GRIDBASED")
    add_dependencies(postprocess post_vector2grid.x)
endif()

# ============================================================================
# Installation
# ============================================================================

install(TARGETS mksrfdata.x mkinidata.x colm.x
    RUNTIME DESTINATION bin
)

install(TARGETS colm
    ARCHIVE DESTINATION lib
)

# ============================================================================
# Print configuration summary
# ============================================================================

message(STATUS "")
message(STATUS "============================================================")
message(STATUS "CoLM CMake Configuration Summary")
message(STATUS "============================================================")
message(STATUS "")
message(STATUS "Spatial Type:        ${SPATIAL_TYPE}")
message(STATUS "LULC Type:           ${LULC_TYPE}")
message(STATUS "Soil Model:          ${SOIL_MODEL}")
message(STATUS "")
message(STATUS "Optional Features:")
message(STATUS "  MPI:               ${ENABLE_MPI}")
message(STATUS "  Urban Model:       ${ENABLE_URBAN_MODEL}")
message(STATUS "  BGC:               ${ENABLE_BGC}")
message(STATUS "  CROP:              ${ENABLE_CROP}")
message(STATUS "  LULCC:             ${ENABLE_LULCC}")
message(STATUS "  Data Assimilation: ${ENABLE_DATA_ASSIMILATION}")
message(STATUS "  CaMa-Flood:        ${ENABLE_CAMA_FLOOD}")
message(STATUS "  Catch Lateral:     ${ENABLE_CATCH_LATERAL_FLOW}")
message(STATUS "  Grid River Lake:   ${ENABLE_GRID_RIVER_LAKE_FLOW}")
message(STATUS "")
message(STATUS "Debug Options:")
message(STATUS "  Debug:             ${ENABLE_DEBUG}")
message(STATUS "  Range Check:       ${ENABLE_RANGE_CHECK}")
message(STATUS "  Srfdata Diag:      ${ENABLE_SRFDATA_DIAG}")
message(STATUS "")
message(STATUS "Compiler:            ${CMAKE_Fortran_COMPILER}")
message(STATUS "Compiler Flags:      ${CMAKE_Fortran_FLAGS}")
message(STATUS "")
message(STATUS "NetCDF Include:      ${NETCDF_INCLUDE_DIRS}")
message(STATUS "NetCDF Libraries:    ${NETCDF_LIBRARIES}")
message(STATUS "")
message(STATUS "============================================================")
message(STATUS "")
message(STATUS "Build targets:")
message(STATUS "  make mksrfdata.x      - Build surface data generator")
message(STATUS "  make mkinidata.x      - Build initial data generator")
message(STATUS "  make colm.x           - Build main CoLM executable")
message(STATUS "  make postprocess      - Build postprocessing tools")
message(STATUS "  make colm             - Build static library")
message(STATUS "  make all              - Build all targets")
message(STATUS "")
message(STATUS "============================================================")
