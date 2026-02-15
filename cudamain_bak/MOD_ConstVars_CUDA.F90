#include <define.h>

MODULE MOD_ConstVars_CUDA

   USE cudafor
   USE MOD_LandPatch, only: numpatch, landpatch
   USE MOD_Vars_Global
   USE MOD_Const_LC
   USE MOD_Const_PFT
   USE MOD_Const_Physical
   USE MOD_TimeManager

   IMPLICIT NONE

! MOD_Namelist-----------------------------------------------------------------
   integer,  constant :: d_numpatch

   type (nl_domain_type), constant :: d_DEF_domain
   type (nl_simulation_time_type), constant :: d_DEF_simulation_time
   type (nl_forcing_type), constant :: d_DEF_forcing

   real(r8), constant :: d_LocalLongitude

   logical,  constant :: d_DEF_USE_VariablySaturatedFlow
   logical,  constant :: d_DEF_USE_PLANTHYDRAULICS
   logical,  constant :: d_DEF_USE_IRRIGATION
   logical,  constant :: d_DEF_Aerosol_Readin
   logical,  constant :: d_DEF_USE_Dynamic_Lake
   logical,  constant :: d_DEF_VEG_SNOW
   logical,  constant :: d_DEF_USE_SNICAR
   logical,  constant :: d_isgreenwich
   logical,  constant :: d_DEF_SPLIT_SOILSNOW
   logical,  constant :: d_DEF_USE_LCT
   logical,  constant :: d_DEF_USE_PFT
   logical,  constant :: d_DEF_USE_PC
   logical,  constant :: d_DEF_USE_CBL_HEIGHT
   logical,  constant :: d_DEF_USE_OZONESTRESS
   logical,  constant :: d_DEF_USE_WUEST
   logical,  constant :: d_DEF_USE_MEDLYNST
   logical,  constant :: d_DEF_USE_OZONEDATA
   logical,  constant :: d_DEF_USE_SUPERCOOL_WATER
   logical,  constant :: d_DEF_URBAN_RUN
   logical,  constant :: d_DEF_Aerosol_Clim

   integer,  constant :: d_DEF_Interception_scheme
   integer,  constant :: d_DEF_precip_phase_discrimination_scheme
   integer,  constant :: d_DEF_RSS_SCHEME
   integer,  constant :: d_DEF_HEIGHT_mode
   integer,  constant :: d_DEF_THERMAL_CONDUCTIVITY_SCHEME
   integer,  constant :: d_DEF_Runoff_SCHEME
   integer,  constant :: d_p_iam_glb

   character(len=256), constant :: d_DEF_dir_runtime

! CoLMMAIN Vars-----------------------------------------------------------------
   integer,  constant :: d_idate(3) ! model calendar for next time step (year, julian day, seconds)
   real(r8), constant :: d_deltim   ! seconds in a time-step
   logical,  constant :: d_dolai    ! true if time for time-varying vegetation parameter
   logical,  constant :: d_doalb    ! true if time for surface albedo calculation
   logical,  constant :: d_dosst    ! true if time for update sst/ice/snow

   real(r8), constant :: &
      d_patchtypes       (N_land_classification) ,&! land patch types
      d_htop0            (N_land_classification) ,&! canopy top height
      d_hbot0            (N_land_classification) ,&! canopy bottom height
      d_fveg0            (N_land_classification) ,&! canopy vegetation fractional cover
      d_sai0             (N_land_classification) ,&! canopy stem area index
      d_chil             (N_land_classification) ,&! leaf angle distribution factor
      d_z0mr             (N_land_classification) ,&! ratio to calculate roughness length z0m
      d_displar          (N_land_classification) ,&! ratio to calculate displacement height d
      d_sqrtdi           (N_land_classification) ,&! inverse sqrt of leaf dimension [m**-0.5]
      d_vmax25           (N_land_classification) ,&! maximum carboxylation rate at 25 C at canopy top
      d_effcon           (N_land_classification) ,&! quantum efficiency
      d_g1               (N_land_classification) ,&! conductance-photosynthesis slope parameter
      d_g0               (N_land_classification) ,&! conductance-photosynthesis intercept
      d_gradm            (N_land_classification) ,&! conductance-photosynthesis slope parameter
      d_binter           (N_land_classification) ,&! conductance-photosynthesis intercept
      d_respcp           (N_land_classification) ,&! respiration fraction
      d_shti             (N_land_classification) ,&! slope of high temperature inhibition function (s1)
      d_slti             (N_land_classification) ,&! slope of low temperature inhibition function (s3)
      d_trda             (N_land_classification) ,&! temperature coefficient in gs-a model (s5)
      d_trdm             (N_land_classification) ,&! temperature coefficient in gs-a model (s6)
      d_trop             (N_land_classification) ,&! temperature coefficient in gs-a model (273.16+25)
      d_hhti             (N_land_classification) ,&! 1/2 point of high temperature inhibition function (s2)
      d_hlti             (N_land_classification) ,&! 1/2 point of low temperature inhibition function (s4)
      d_extkn            (N_land_classification) ,&! coefficient of leaf nitrogen allocation
      d_lambda           (N_land_classification) ,&! marginal water cost of carbon gain (mol mol-1)
      d_d50              (N_land_classification) ,&! depth at 50% roots
      d_beta             (N_land_classification) ,&! coefficient of root profile
      d_kmax_sun         (N_land_classification) ,&! Plant Hydraulics Parameters (TODO@Xingjie Lu, please give more details and below)
      d_kmax_sha         (N_land_classification) ,&! Plant Hydraulics Parameters
      d_kmax_xyl         (N_land_classification) ,&! Plant Hydraulics Parameters
      d_kmax_root        (N_land_classification) ,&! Plant Hydraulics Parameters
      d_psi50_sun        (N_land_classification) ,&! water potential at 50% loss of sunlit leaf tissue conductance (mmH2O)
      d_psi50_sha        (N_land_classification) ,&! water potential at 50% loss of shaded leaf tissue conductance (mmH2O)
      d_psi50_xyl        (N_land_classification) ,&! water potential at 50% loss of xylem tissue conductance (mmH2O)
      d_psi50_root       (N_land_classification) ,&! water potential at 50% loss of root tissue conductance (mmH2O)
      d_ck               (N_land_classification) ,&! shape-fitting parameter for vulnerability curve (-)
      d_rootfr   (nl_soil,N_land_classification) ,&! fraction of roots in each soil layer
      d_rho          (2,2,N_land_classification) ,&! leaf reflectance (iw=iband, il=life and dead)
      d_tau          (2,2,N_land_classification)   ! leaf transmittance (iw=iband, il=life and dead)

! MOD_Vars_TimeInvariants-----------------------------------------------------------------
   real(r8), constant :: &
      d_zlnd                                     ,&!roughness length for soil [m]
      d_zsno                                     ,&!roughness length for snow [m]
      d_csoilc                                   ,&!drag coefficient for soil under canopy [-]
      d_dewmx                                    ,&!maximum dew
      d_capr                                     ,&!tuning factor to turn first layer T into surface T
      d_cnfac                                    ,&!Crank Nicholson factor between 0 and 1
      d_ssi                                      ,&!irreducible water saturation of snow
      d_wimp                                     ,&!water impermeable IF porosity less than wimp
      d_pondmx                                   ,&!ponding depth (mm)
      d_smpmax                                   ,&!wilting point potential in mm
      d_smpmin                                   ,&!restriction for min of soil poten. (mm)
      d_smpmax_hr                                ,&!wilting point potential in mm for heterotrophic respiration
      d_smpmin_hr                                ,&!restriction for min of soil poten for heterotrophic respiration. (mm)
      d_trsmx0                                   ,&!max transpiration for moist soil+100% veg.  [mm/s]
      d_tcrit                                    ,&!critical temp. to determine rain or snow
      d_wetwatmax                                  !maximum wetland water (mm)

! MOD_Vars_Global-----------------------------------------------------------------
   real(r8), constant :: &
      d_z_soi (1:nl_soil)                        ,&! node depth [m]
      d_dz_soi(1:nl_soil)                        ,&! soil node thickness [m]
      d_zi_soi(1:nl_soil)                          ! interface level below a zsoi level [m]

! MOD_Vars_1DFluxes-----------------------------------------------------------------------
   integer, parameter :: nsensor = 1

CONTAINS

   SUBROUTINE const_var_init (idate, deltim, dolai, doalb, dosst)

      USE MOD_Precision
      USE MOD_Namelist

      USE MOD_Vars_TimeInvariants

      USE MOD_UserSpecifiedForcing, only: HEIGHT_mode

      USE MOD_SPMD_Task_CUDA

      IMPLICIT NONE

      integer,  intent(in) :: idate(3) ! model calendar for next time step (year, julian day, seconds)
      real(r8), intent(in) :: deltim
      logical,  intent(in) :: dolai    ! true if time for time-varying vegetation parameter
      logical,  intent(in) :: doalb    ! true if time for surface albedo calculation
      logical,  intent(in) :: dosst    ! true if time for update sst/ice/snow

      d_idate(:) = idate(:)
      d_deltim   = deltim
      d_dolai    = dolai
      d_doalb    = doalb
      d_dosst    = dosst

      d_numpatch = numpatch

      d_DEF_domain = DEF_domain
      d_DEF_simulation_time = DEF_simulation_time
      d_DEF_forcing = DEF_forcing

      d_LocalLongitude = LocalLongitude

      d_DEF_USE_VariablySaturatedFlow = DEF_USE_VariablySaturatedFlow
      d_DEF_USE_PLANTHYDRAULICS = DEF_USE_PLANTHYDRAULICS
      d_DEF_USE_IRRIGATION = DEF_USE_IRRIGATION
      d_DEF_Aerosol_Readin = DEF_Aerosol_Readin
      d_DEF_USE_Dynamic_Lake = DEF_USE_Dynamic_Lake
      d_DEF_VEG_SNOW = DEF_VEG_SNOW
      d_DEF_USE_SNICAR = DEF_USE_SNICAR
      d_isgreenwich = isgreenwich
      d_DEF_USE_LCT = DEF_USE_LCT
      d_DEF_USE_PFT = DEF_USE_PFT
      d_DEF_USE_PC = DEF_USE_PC
      d_DEF_SPLIT_SOILSNOW = DEF_SPLIT_SOILSNOW
      d_DEF_USE_CBL_HEIGHT = DEF_USE_CBL_HEIGHT
      d_DEF_USE_OZONESTRESS = DEF_USE_OZONESTRESS
      d_DEF_USE_WUEST = DEF_USE_WUEST
      d_DEF_USE_MEDLYNST = DEF_USE_MEDLYNST
      d_DEF_USE_OZONEDATA = DEF_USE_OZONEDATA
      d_DEF_USE_SUPERCOOL_WATER = DEF_USE_SUPERCOOL_WATER
      d_DEF_URBAN_RUN = DEF_URBAN_RUN
      d_DEF_Aerosol_Clim  = DEF_Aerosol_Clim

      d_DEF_Interception_scheme = DEF_Interception_scheme
      d_DEF_RSS_SCHEME = DEF_RSS_SCHEME
      d_DEF_THERMAL_CONDUCTIVITY_SCHEME = DEF_THERMAL_CONDUCTIVITY_SCHEME
      d_DEF_Runoff_SCHEME = DEF_Runoff_SCHEME
      d_p_iam_glb = p_iam_glb

      d_DEF_dir_runtime = DEF_dir_runtime

      IF (trim(DEF_precip_phase_discrimination_scheme) == 'I') THEN
         d_DEF_precip_phase_discrimination_scheme = 1
      ELSEIF (trim(DEF_precip_phase_discrimination_scheme) == 'II') THEN
         d_DEF_precip_phase_discrimination_scheme = 2
      ELSEIF (trim(DEF_precip_phase_discrimination_scheme) == 'III') THEN
         d_DEF_precip_phase_discrimination_scheme = 3
      ELSE
         d_DEF_precip_phase_discrimination_scheme = 0
      ENDIF

      IF (trim(HEIGHT_mode) == 'absolute') THEN
         d_DEF_HEIGHT_mode = 1
      ELSE
         d_DEF_HEIGHT_mode = 0
      ENDIF

      d_rootfr       = rootfr
      d_sqrtdi       = sqrtdi
      d_effcon       = effcon
      d_vmax25       = vmax25
      d_kmax_sun     = kmax_sun
      d_kmax_sha     = kmax_sha
      d_kmax_xyl     = kmax_xyl
      d_kmax_root    = kmax_root
      d_psi50_sun    = psi50_sun
      d_psi50_sha    = psi50_sha
      d_psi50_xyl    = psi50_xyl
      d_psi50_root   = psi50_root
      d_ck           = ck
      d_slti         = slti
      d_hlti         = hlti
      d_shti         = shti
      d_hhti         = hhti
      d_trda         = trda
      d_trdm         = trdm
      d_trop         = trop
      d_g1           = g1
      d_g0           = g0
      d_gradm        = gradm
      d_binter       = binter
      d_extkn        = extkn
      d_lambda       = lambda
      d_chil         = chil
      d_rho          = rho
      d_tau          = tau

      d_zlnd   = zlnd
      d_zsno   = zsno
      d_csoilc = csoilc
      d_dewmx  = dewmx
      d_capr   = capr
      d_cnfac  = cnfac
      d_ssi    = ssi
      d_wimp   = wimp
      d_pondmx = pondmx
      d_smpmax = smpmax
      d_smpmin = smpmin
      d_trsmx0 = trsmx0
      d_tcrit  = tcrit

      d_z_soi  = z_soi
      d_dz_soi = dz_soi
      d_zi_soi = zi_soi

   END SUBROUTINE const_var_init

END MODULE MOD_ConstVars_CUDA