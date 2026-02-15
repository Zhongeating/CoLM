# ============================================================================
# CoLM Parallel Makefile with Precise Dependencies
# Supports parallel compilation: make -j N
# Supports conditional compilation based on include/define.h
# ============================================================================

include include/Makeoptions
HEADER = include/define.h

VPATH = include : share : mksrfdata : mkinidata \
	: main : main/HYDRO : main/BGC : main/URBAN : main/LULCC : main/DA \
	: extends/CaMa/src : postprocess : .bld : cudamain

.PHONY: all
# all: config.mk mkdir_build mksrfdata.x mkinidata.x colm.x postprocess.x lib
all: config.mk mkdir_build colm.x
	@echo ''
	@echo '*******************************************************'
	@echo '*                                                     *'
	@echo '*        Making all CoLM programs successfully.       *'
	@echo '*                                                     *'
	@echo '*******************************************************'
	@echo '*   Spatial: $(SPATIAL_TYPE)'
	@echo '*   BGC     =$(BGC_ENABLED)'
	@echo '*   URBAN   =$(URBAN_ENABLED)'
	@echo '*   LULCC   =$(LULCC_ENABLED)'
	@echo '*   DA      =$(DA_ENABLED)'
	@echo '*   MPI     =$(USEMPI_ENABLED)'
	@echo '*   CaMa    =$(CAMA_ENABLED)'
	@echo ''

-include config.mk

.PHONY: config.mk
config.mk:
	@echo "Preprocessing config.mk..."
	@${FF} -E -cpp config.f90 | grep -v '^[[:space:]]*!' | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$$' > $@

.PHONY: mkdir_build
mkdir_build:
	@mkdir -p .bld

# ============================================================================
# Include Auto-Generated Dependencies (if available)
# ============================================================================

-include Makefile.deps

# ============================================================================
# SHARED MODULES - Hierarchical Dependencies
# ============================================================================

# Level 0: Foundation (no dependencies)
OBJS_L0 = MOD_Precision.o MOD_IncompleteGamma.o

# Level 1: Basic utilities
OBJS_L1 = MOD_SPMD_Task.o MOD_Namelist.o MOD_UserDefFun.o MOD_Const_Physical.o

# Level 2: Core infrastructure
OBJS_L2 = MOD_Vars_Global.o MOD_Utils.o MOD_TimeManager.o MOD_Const_LC.o

# Level 3: I/O and data structures
OBJS_L3 = MOD_NetCDFSerial.o MOD_Block.o MOD_Grid.o MOD_Pixel.o MOD_DataType.o

# Level 4: Advanced I/O
OBJS_L4 = MOD_NetCDFPoint.o MOD_NetCDFBlock.o MOD_CatchmentDataReadin.o MOD_5x5DataReadin.o \
          MOD_Mesh.o MOD_Pixelset.o MOD_NetCDFVector.o MOD_RangeCheck.o MOD_SpatialMapping.o

# Level 5: High-level data management
OBJS_L5 = MOD_WorkerPushData.o MOD_AggregationRequestData.o MOD_PixelsetShared.o \
          MOD_LandElm.o MOD_LandHRU.o MOD_Landpatch.o MOD_Land2mWMO.o \
          MOD_LandCrop.o MOD_LandPFT.o MOD_LandUrban.o MOD_Urban_Const_LCZ.o \
          MOD_SingleSrfdata.o MOD_SrfdataDiag.o MOD_SrfdataRestart.o \
          MOD_ElmVector.o MOD_HRUVector.o MOD_MeshFilter.o MOD_RegionClip.o

# Combine shared objects
OBJS_SHARED = $(OBJS_L0) $(OBJS_L1) $(OBJS_L2) $(OBJS_L3) $(OBJS_L4) $(OBJS_L5)
OBJS_SHARED_T = $(addprefix .bld/,$(OBJS_SHARED))

# ============================================================================
# MKSRFDATA Modules
# ============================================================================

OBJS_MKSRFDATA = \
	Aggregation_PercentagesPFT.o \
	Aggregation_LAI.o \
	Aggregation_SoilBrightness.o \
	Aggregation_LakeDepth.o \
	Aggregation_ForestHeight.o \
	Aggregation_SoilParameters.o \
	Aggregation_DBedrock.o \
	Aggregation_Topography.o \
	Aggregation_TopoWetness.o \
	Aggregation_TopographyFactors.o \
	Aggregation_TopographyFactors_Simple.o \
	Aggregation_Urban.o \
	Aggregation_SoilTexture.o \
	MOD_Lulcc_TransferTrace.o

OBJS_MKSRFDATA_T = $(addprefix .bld/,$(OBJS_MKSRFDATA))

# Generic rule for aggregation modules
.bld/Aggregation_%.o: mksrfdata/Aggregation_%.F90 ${HEADER} ${OBJS_SHARED_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

.bld/MKSRFDATA.o: mksrfdata/MKSRFDATA.F90 ${HEADER} ${OBJS_SHARED_T} ${OBJS_MKSRFDATA_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

OBJS_MKSRFDATA += MKSRFDATA.o
OBJS_MKSRFDATA_T = $(addprefix .bld/,$(OBJS_MKSRFDATA))

# ============================================================================
# BASIC Modules (for main and mkinidata)
# ============================================================================

# Core basic modules
OBJS_BASIC_CORE = \
	MOD_Vector_ReadWrite.o \
	MOD_Const_PFT.o \
	MOD_Vars_1DForcing.o \
	MOD_Vars_2DForcing.o \
	MOD_Vars_1DPFTFluxes.o

# Conditional basic modules
ifeq ($(BGC_ENABLED),YES)
OBJS_BASIC_BGC = \
	MOD_BGC_Vars_1DFluxes.o \
	MOD_BGC_Vars_1DPFTFluxes.o \
	MOD_BGC_Vars_PFTimeVariables.o \
	MOD_BGC_Vars_TimeInvariants.o \
	MOD_BGC_Vars_TimeVariables.o
else
OBJS_BASIC_BGC =
endif

ifeq ($(URBAN_ENABLED),YES)
OBJS_BASIC_URBAN = \
	MOD_Urban_Vars_1DFluxes.o \
	MOD_Urban_Vars_TimeVariables.o \
	MOD_Urban_Vars_TimeInvariants.o
else
OBJS_BASIC_URBAN =
endif

ifeq ($(DA_ENABLED),YES)
OBJS_BASIC_DA = \
	MOD_DA_Vars_1DFluxes.o \
	MOD_DA_Vars_TimeVariables.o
else
OBJS_BASIC_DA =
endif

# Catchment modules
ifeq ($(SPATIAL_TYPE),catchment)
OBJS_BASIC_CATCH = \
	MOD_Catch_BasinNetwork.o \
	MOD_Catch_Vars_TimeVariables.o \
	MOD_Catch_Vars_1DFluxes.o
else
OBJS_BASIC_CATCH =
endif

# Grid river modules
ifneq ($(SPATIAL_TYPE),singlepoint)
OBJS_BASIC_RIVER = \
	MOD_Grid_RiverLakeNetwork.o \
	MOD_Grid_Reservoir.o \
	MOD_Grid_RiverLakeTimeVars.o
else
OBJS_BASIC_RIVER =
endif

# Extended basic modules
OBJS_BASIC_EXT = \
	MOD_Vars_TimeInvariants.o \
	MOD_Vars_TimeVariables.o \
	MOD_Vars_1DFluxes.o \
	MOD_Hydro_SoilFunction.o \
	MOD_Hydro_SoilWater.o \
	MOD_Eroot.o \
	MOD_Qsadv.o \
	MOD_LAIEmpirical.o \
	MOD_LAIReadin.o \
	MOD_OrbCoszen.o \
	MOD_OrbCosazi.o \
	MOD_3DCanopyRadiation.o \
	MOD_Aerosol.o \
	MOD_SnowSnicar.o \
	MOD_Albedo.o \
	MOD_SnowFraction.o \
	MOD_MonthlyinSituCO2MaunaLoa.o

# Data reading modules
OBJS_BASIC_IO = \
	MOD_PercentagesPFTReadin.o \
	MOD_LakeDepthReadin.o \
	MOD_DBedrockReadin.o \
	MOD_SoilColorRefl.o \
	MOD_SoilParametersReadin.o \
	MOD_SoilTextureReadin.o \
	MOD_HtopReadin.o \
	MOD_CropReadin.o \
	MOD_NitrifData.o \
	MOD_NdepData.o \
	MOD_FireData.o

# Urban reading modules
ifeq ($(URBAN_ENABLED),YES)
OBJS_BASIC_IO += \
	MOD_Urban_LAIReadin.o \
	MOD_Urban_Shortwave.o \
	MOD_Urban_Albedo.o \
	MOD_UrbanReadin.o
endif

# BGC summary
ifeq ($(BGC_ENABLED),YES)
OBJS_BASIC_IO += MOD_BGC_CNSummary.o
endif

# Initialization modules
OBJS_BASIC_INIT = \
	MOD_IniTimeVariable.o \
	MOD_UrbanIniTimeVariable.o \
	MOD_ElementNeighbour.o \
	MOD_VicParaReadin.o \
	MOD_Initialize.o

# Catchment network modules
ifeq ($(SPATIAL_TYPE),catchment)
OBJS_BASIC_INIT += \
	MOD_Catch_HillslopeNetwork.o \
	MOD_Catch_RiverLakeNetwork.o \
	MOD_Catch_Reservoir.o
endif

# Combine all basic modules
OBJS_BASIC = $(OBJS_BASIC_CORE) $(OBJS_BASIC_BGC) $(OBJS_BASIC_URBAN) $(OBJS_BASIC_DA) \
             $(OBJS_BASIC_CATCH) $(OBJS_BASIC_RIVER) $(OBJS_BASIC_EXT) $(OBJS_BASIC_IO) $(OBJS_BASIC_INIT)

OBJS_BASIC_T = $(addprefix .bld/,$(OBJS_BASIC))

# ============================================================================
# MKINIDATA Modules
# ============================================================================

.bld/CoLMINI.o: mkinidata/CoLMINI.F90 ${HEADER} ${OBJS_SHARED_T} ${OBJS_BASIC_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

OBJS_MKINIDATA = CoLMINI.o
OBJS_MKINIDATA_T = $(addprefix .bld/,$(OBJS_MKINIDATA))

# ============================================================================
# CaMa-Flood Modules (Conditional)
# ============================================================================

ifeq ($(CAMA_ENABLED),YES)
OBJECTS_CAMA = \
	parkind1.o \
	yos_cmf_input.o \
	yos_cmf_time.o \
	yos_cmf_map.o \
	yos_cmf_prog.o \
	yos_cmf_diag.o \
	cmf_utils_mod.o \
	cmf_calc_outflw_mod.o \
	cmf_calc_pthout_mod.o \
	cmf_calc_fldstg_mod.o \
	cmf_calc_stonxt_mod.o \
	cmf_opt_outflw_mod.o \
	cmf_ctrl_tracer_mod.o \
	cmf_ctrl_mpi_mod.o \
	cmf_ctrl_damout_mod.o \
	cmf_ctrl_levee_mod.o \
	cmf_ctrl_forcing_mod.o \
	cmf_ctrl_boundary_mod.o \
	cmf_ctrl_output_mod.o \
	cmf_ctrl_restart_mod.o \
	cmf_ctrl_sed_mod.o \
	cmf_calc_diag_mod.o \
	cmf_ctrl_physics_mod.o \
	cmf_ctrl_time_mod.o \
	cmf_ctrl_maps_mod.o \
	cmf_ctrl_vars_mod.o \
	cmf_ctrl_nmlist_mod.o \
	cmf_drv_control_mod.o \
	cmf_drv_advance_mod.o

$(addprefix .bld/,$(OBJECTS_CAMA)): .bld/%.o: %.F90 ${HEADER}
	$(FCMP) -c ${FFLAGS} $(MODS) ${CFLAGS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

OBJS_CAMA_T = $(addprefix .bld/,$(OBJECTS_CAMA))
endif

# ============================================================================
# MAIN Program Modules
# ============================================================================

# Physics modules (always compiled)
OBJS_PHYSICS = \
	MOD_AssimStomataConductance.o \
	MOD_PlantHydraulic.o \
	MOD_FrictionVelocity.o \
	MOD_TurbulenceLEddy.o \
	MOD_Ozone.o \
	MOD_CanopyLayerProfile.o \
	MOD_LeafTemperature.o \
	MOD_LeafTemperaturePC.o \
	MOD_SoilThermalParameters.o \
	MOD_Runoff.o \
	MOD_SoilSnowHydrology.o \
	MOD_SnowLayersCombineDivide.o \
	MOD_PhaseChange.o \
	MOD_Glacier.o \
	MOD_Lake.o \
	MOD_SimpleOcean.o \
	MOD_GroundFluxes.o \
	MOD_GroundTemperature.o \
	MOD_LeafInterception.o \
	MOD_NetSolar.o \
	MOD_WetBulb.o \
	MOD_RainSnowTemp.o \
	MOD_SoilSurfaceResistance.o \
	MOD_NewSnow.o \
	MOD_Thermal.o

# VIC hydrology (conditional)
OBJS_PHYSICS += MOD_Hydro_VIC_Variables.o MOD_Hydro_VIC.o

# Catchment hydrology modules
ifeq ($(SPATIAL_TYPE),catchment)
OBJS_HYDRO = \
	MOD_Catch_HillslopeFlow.o \
	MOD_Catch_SubsurfaceFlow.o \
	MOD_Catch_RiverLakeFlow.o \
	MOD_Catch_Hist.o \
	MOD_Catch_WriteParameters.o
else
OBJS_HYDRO =
endif

# Grid river modules
ifneq ($(SPATIAL_TYPE),singlepoint)
OBJS_GRID_RIVER = MOD_Grid_RiverLakeHist.o
ifeq ($(GRID_RIVER),YES)
OBJS_GRID_RIVER += MOD_Grid_RiverLakeFlow.o
endif
else
OBJS_GRID_RIVER =
endif

# BGC modules (conditional)
ifeq ($(BGC_ENABLED),YES)
OBJS_BGC = \
	MOD_BGC_CNCStateUpdate1.o \
	MOD_BGC_CNCStateUpdate2.o \
	MOD_BGC_CNCStateUpdate3.o \
	MOD_BGC_CNNStateUpdate1.o \
	MOD_BGC_CNNStateUpdate2.o \
	MOD_BGC_CNNStateUpdate3.o \
	MOD_BGC_Soil_BiogeochemNStateUpdate1.o \
	MOD_BGC_Soil_BiogeochemNitrifDenitrif.o \
	MOD_BGC_Soil_BiogeochemCompetition.o \
	MOD_BGC_Soil_BiogeochemDecompCascadeBGC.o \
	MOD_BGC_Soil_BiogeochemDecomp.o \
	MOD_BGC_Soil_BiogeochemLittVertTransp.o \
	MOD_BGC_Soil_BiogeochemNLeaching.o \
	MOD_BGC_Soil_BiogeochemPotential.o \
	MOD_BGC_Soil_BiogeochemVerticalProfile.o \
	MOD_BGC_Veg_CNGapMortality.o \
	MOD_BGC_Veg_CNGResp.o \
	MOD_BGC_Veg_CNMResp.o \
	MOD_BGC_Daylength.o \
	MOD_BGC_Veg_CNPhenology.o \
	MOD_BGC_Veg_NutrientCompetition.o \
	MOD_BGC_Veg_CNVegStructUpdate.o \
	MOD_BGC_CNAnnualUpdate.o \
	MOD_BGC_CNZeroFluxes.o \
	MOD_BGC_CNBalanceCheck.o \
	MOD_BGC_CNSASU.o \
	MOD_BGC_Veg_CNNDynamics.o \
	MOD_BGC_Veg_CNFireBase.o \
	MOD_BGC_Veg_CNFireLi2016.o

OBJS_BGC_T = $(addprefix .bld/,$(OBJS_BGC))
.bld/MOD_BGC_driver.o: main/BGC/MOD_BGC_driver.F90 ${HEADER} ${OBJS_SHARED_T} ${OBJS_BGC_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

OBJS_URBAN += MOD_BGC_driver.o
OBJS_URBAN_T = $(addprefix .bld/,$(OBJS_URBAN))
else
OBJS_BGC =
endif

# Urban modules (conditional)
ifeq ($(URBAN_ENABLED),YES)
OBJS_URBAN = \
	MOD_Urban_Longwave.o \
	MOD_Urban_NetSolar.o \
	MOD_Urban_Flux.o \
	MOD_Urban_GroundFlux.o \
	MOD_Urban_RoofFlux.o \
	MOD_Urban_RoofTemperature.o \
	MOD_Urban_WallTemperature.o \
	MOD_Urban_PerviousTemperature.o \
	MOD_Urban_ImperviousTemperature.o \
	MOD_Urban_Hydrology.o \
	MOD_Urban_BEM.o \
	MOD_Urban_LUCY.o \
	MOD_Urban_Thermal.o

.bld/MOD_Urban_%.o: main/URBAN/MOD_Urban_%.F90 ${HEADER} ${OBJS_SHARED_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

OBJS_URBAN_T = $(addprefix .bld/,$(OBJS_URBAN))
	
.bld/CoLMMAIN_Urban.o: main/URBAN/CoLMMAIN_Urban.F90 ${HEADER} ${OBJS_SHARED_T} ${OBJS_URBAN_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

OBJS_URBAN += CoLMMAIN_Urban.o
OBJS_URBAN_T = $(addprefix .bld/,$(OBJS_URBAN))
else
OBJS_URBAN =
endif

# LULCC modules (conditional)
ifeq ($(LULCC_ENABLED),YES)
OBJS_LULCC = \
	MOD_Lulcc_Vars_TimeInvariants.o \
	MOD_Lulcc_Vars_TimeVariables.o \
	MOD_Lulcc_TransferTraceReadin.o \
	MOD_Lulcc_MassEnergyConserve.o \
	MOD_Lulcc_Initialize.o \
	MOD_Lulcc_Driver.o

.bld/MOD_LULCC_%.o: main/LULCC/MOD_LULCC_%.F90 ${HEADER} ${OBJS_SHARED_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld
else
OBJS_LULCC =
endif

# DA modules (conditional)
ifeq ($(DA_ENABLED),YES)
OBJS_DA = \
	MOD_DA_Const.o \
	MOD_DA_RTM.o \
	MOD_DA_EnKF.o \
	MOD_DA_TWS.o \
	MOD_DA_SM.o \
	MOD_DA_Ensemble.o \
	MOD_DA_Main.o

.bld/MOD_DA_%.o: main/DA/MOD_DA_%.F90 ${HEADER} ${OBJS_SHARED_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld
else
OBJS_DA =
endif

# Forcing and output modules
OBJS_IO = \
	MOD_UserSpecifiedForcing.o \
	MOD_ForcingDownscaling.o \
	MOD_Forcing.o \
	MOD_Vars_1DAccFluxes.o \
	MOD_Irrigation.o \
	MOD_HistWriteBack.o \
	MOD_HistGridded.o \
	MOD_HistVector.o \
	MOD_HistSingle.o \
	MOD_Hist.o \
	MOD_CheckEquilibrium.o \
	MOD_LightningData.o

# CaMa coupling
ifeq ($(CAMA_ENABLED),YES)
OBJS_IO += MOD_CaMa_Vars.o MOD_CaMa_colmCaMa.o
endif

# Catchment lateral flow
ifeq ($(CATCH_LATERAL),YES)
OBJS_CATCH_FLOW = MOD_Catch_LateralFlow.o
else
OBJS_CATCH_FLOW =
endif

# Combine all main objects
OBJS_MAIN = $(OBJS_PHYSICS) $(OBJS_HYDRO) $(OBJS_GRID_RIVER) $(OBJS_BGC) $(OBJS_URBAN) \
            $(OBJS_LULCC) $(OBJS_DA) $(OBJS_IO) $(OBJS_CATCH_FLOW) $(OBJS_DRIVER)

OBJS_MAIN_T = $(addprefix .bld/,$(OBJS_MAIN))

.bld/CoLMMAIN.o: main/CoLMMAIN.F90 ${HEADER} ${OBJS_SHARED_T} ${OBJS_BASIC_T} ${OBJS_MAIN_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

.bld/MOD_CoLMMAIN_CUDA.o: cudamain/MOD_CoLMMAIN_CUDA.F90 ${HEADER} ${OBJS_SHARED_T} ${OBJS_BASIC_T} ${OBJS_MAIN_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

.bld/CoLMDRIVER.o: main/CoLMDRIVER.F90 ${HEADER} ${OBJS_SHARED_T} ${OBJS_BASIC_T} ${OBJS_MAIN_T} .bld/CoLMMAIN.o .bld/MOD_CoLMMAIN_CUDA.o
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

.bld/CoLM.o: main/CoLM.F90 ${HEADER} ${OBJS_SHARED_T} ${OBJS_BASIC_T} ${OBJS_MAIN_T} .bld/CoLMDRIVER.o
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

OBJS_MAIN += \
	CoLMMAIN.o \
	MOD_CoLMMAIN_CUDA.o \
	CoLMDRIVER.o \
	CoLM.o

OBJS_MAIN_T = $(addprefix .bld/,$(OBJS_MAIN))

# ============================================================================
# Main Targets
# ============================================================================

.PHONY: mksrfdata.x
mksrfdata.x: mkdir_build ${HEADER} ${OBJS_SHARED_T} ${OBJS_MKSRFDATA_T}
	@echo 'Making CoLM surface data start >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
	${FF} ${FOPTS} ${OBJS_SHARED_T} ${OBJS_MKSRFDATA_T} -o run/mksrfdata.x ${LDFLAGS}
	@echo '<<<<<<<<<<<<<<<<<<<<<<<<<< Making CoLM surface data completed!'

.PHONY: mkinidata.x
mkinidata.x: mkdir_build ${HEADER} ${OBJS_SHARED_T} ${OBJS_BASIC_T} ${OBJS_MKINIDATA_T}
	@echo 'Making CoLM initial data start >>>>>>>>>>>>>>>>>>>>>>>>>>>>'
	${FF} ${FOPTS} ${OBJS_SHARED_T} ${OBJS_BASIC_T} ${OBJS_MKINIDATA_T} -o run/mkinidata.x ${LDFLAGS}
	@echo '<<<<<<<<<<<<<<<<<<<<<<<<< Making CoLM initial data completed!'

.PHONY: colm.x
ifeq ($(CAMA_ENABLED),YES)
colm.x: mkdir_build ${HEADER} ${OBJS_SHARED_T} ${OBJS_CAMA_T} ${OBJS_BASIC_T} ${OBJS_MAIN_T}
	@echo 'Making CoLM with CaMa start >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
	${FF} ${FOPTS} ${OBJS_SHARED_T} ${OBJS_BASIC_T} ${OBJS_CAMA_T} ${OBJS_MAIN_T} -o run/colm.x ${LDFLAGS}
	@echo '<<<<<<<<<<<<<<<<<<<<<<<<<<<< Making CoLM with CaMa completed!'
else
colm.x: mkdir_build ${HEADER} ${OBJS_SHARED_T} ${OBJS_BASIC_T} ${OBJS_MAIN_T}
	@echo 'Making CoLM start >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
	${FF} ${FOPTS} ${OBJS_SHARED_T} ${OBJS_BASIC_T} ${OBJS_MAIN_T} -o run/colm.x ${LDFLAGS}
	@echo '<<<<<<<<<<<<<<<<<<<<<<<<<<<<< Making CoLM completed!'
endif

# ============================================================================
# POSTPROCESS Modules
# ============================================================================

OBJS_POST1 = MOD_Concatenate.o HistConcatenate.o
OBJS_POST2 = MOD_Vector2Grid.o POST_Vector2Grid.o
OBJS_POST3 = SrfDataConcatenate.o

.bld/SrfDataConcatenate.o: postprocess/SrfDataConcatenate.F90 ${HEADER} ${OBJS_SHARED_T}
	${FF} -c ${FOPTS} $(INCLUDE_DIR) -o $@ $< ${MOD_CMD}.bld

OBJS_POST1_T = $(addprefix .bld/,$(OBJS_POST1))
OBJS_POST2_T = $(addprefix .bld/,$(OBJS_POST2))
OBJS_POST3_T = $(addprefix .bld/,$(OBJS_POST3))

hist_concatenate.x: ${HEADER} ${OBJS_SHARED_T} ${OBJS_POST1_T}
	${FF} ${FOPTS} ${OBJS_SHARED_T} ${OBJS_POST1_T} -o run/$@ ${LDFLAGS}

post_vector2grid.x: ${HEADER} ${OBJS_SHARED_T} ${OBJS_POST2_T}
	${FF} ${FOPTS} ${OBJS_SHARED_T} ${OBJS_POST2_T} -o run/$@ ${LDFLAGS}

srfdata_concatenate.x: ${HEADER} ${OBJS_SHARED_T} ${OBJS_POST3_T}
	${FF} ${FOPTS} ${OBJS_SHARED_T} ${OBJS_POST3_T} -o run/$@ ${LDFLAGS}

.PHONY: postprocess.x
ifneq ($(SPATIAL_TYPE),gridbased)
postprocess.x: mkdir_build hist_concatenate.x srfdata_concatenate.x post_vector2grid.x
	@echo '<<<<<<<<<<<<<<<<<<<<<<<<< Making CoLM postprocessing completed!'
else
postprocess.x: mkdir_build hist_concatenate.x srfdata_concatenate.x
	@echo '<<<<<<<<<<<<<<<<<<<<<<<<< Making CoLM postprocessing completed!'
endif

# ============================================================================
# Static Library
# ============================================================================

.PHONY: lib
lib: ${OBJS_SHARED_T} ${OBJS_BASIC_T}
	@echo 'Making CoLM static library >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
	@mkdir -p lib
	@cd lib && find ../.bld -name "*.o" ! -name "CoLM.o" ! -name "MKSRFDATA.o" ! -name "CoLMINI.o" -exec ln -sf {} ./ \;
	@cd lib && ar rc libcolm.a *.o && ranlib libcolm.a
	@ln -sf lib/libcolm.a ./libcolm.a
	@echo '<<<<<<<<<<<<<<<<<<<<<<<<< Making CoLM static library completed!'

# ============================================================================
# Clean Targets
# ============================================================================

.PHONY: clean
clean:
	rm -rf .bld lib libcolm.a
	rm -f run/mksrfdata.x run/mkinidata.x run/colm.x
	rm -f run/hist_concatenate.x run/srfdata_concatenate.x run/post_vector2grid.x
	rm -f extends/CaMa/src/*.o extends/CaMa/src/*.mod extends/CaMa/src/*.a

# ============================================================================
# Help and Information
# ============================================================================

.PHONY: help
help:
	@echo "============================================================"
	@echo "CoLM Parallel Makefile"
	@echo "============================================================"
	@echo ""
	@echo "Current Configuration (from $(HEADER)):"
	@echo "  Spatial Type:        $(SPATIAL_TYPE)"
	@echo "  BGC Model:           $(BGC_ENABLED)"
	@echo "  Urban Model:         $(URBAN_ENABLED)"
	@echo "  LULCC:               $(LULCC_ENABLED)"
	@echo "  Data Assimilation:   $(DA_ENABLED)"
	@echo "  MPI Parallel:        $(USEMPI_ENABLED)"
	@echo "  CaMa-Flood:          $(CAMA_ENABLED)"
	@echo "  Catchment Lateral:   $(CATCH_LATERAL)"
	@echo "  Grid River Lake:     $(GRID_RIVER)"
	@echo ""
	@echo "Build Targets:"
	@echo "  all              - Build all executables and library"
	@echo "  mksrfdata.x      - Build surface data generator"
	@echo "  mkinidata.x      - Build initial data generator"
	@echo "  colm.x           - Build main CoLM executable"
	@echo "  postprocess.x    - Build postprocessing tools"
	@echo "  lib              - Build static library"
	@echo ""
	@echo "Maintenance:"
	@echo "  clean            - Remove build artifacts"
	@echo "  help             - Show this help"
	@echo ""
	@echo "Parallel Compilation:"
	@echo "  make -j 4 all    - Build with 4 parallel jobs"
	@echo "  make -j 8 all    - Build with 8 parallel jobs"
	@echo "  make -j all      - Build with max parallel jobs"
	@echo ""
	@echo "Adding New Modules:"
	@echo "  1. Place source file in appropriate directory:"
	@echo "     - share/       : Shared utilities"
	@echo "     - main/        : Core physics"
	@echo "     - main/BGC/    : Biogeochemistry (if BGC enabled)"
	@echo "     - main/URBAN/  : Urban model (if URBAN enabled)"
	@echo "     - main/HYDRO/  : Hydrology"
	@echo "     - main/DA/     : Data assimilation (if DA enabled)"
	@echo "     - main/LULCC/  : Land use change (if LULCC enabled)"
	@echo "  2. Add module to appropriate OBJS_* variable above"
	@echo "  3. For conditional modules, add to ifeq block"
	@echo "  4. Run: make clean && make -j all"
	@echo ""
	@echo "Module Dependency Levels:"
	@echo "  Level 0: Foundation (MOD_Precision, etc.)"
	@echo "  Level 1: Basic utilities (MOD_SPMD_Task, MOD_Namelist)"
	@echo "  Level 2: Core infrastructure (MOD_Vars_Global, MOD_Utils)"
	@echo "  Level 3: I/O and data structures"
	@echo "  Level 4: Advanced data structures"
	@echo "  Level 5: High-level management"
	@echo "  BASIC:   Application-specific modules"
	@echo "  MAIN:    Physics and driver modules"
	@echo ""
	@echo "Conditional Compilation:"
	@echo "  Edit include/define.h to enable/disable features"
	@echo "  Makefile automatically detects settings"
	@echo "============================================================"

.PHONY: info
info: Help
