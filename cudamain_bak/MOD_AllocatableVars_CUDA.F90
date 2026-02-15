#include <define.h>

MODULE MOD_AllocatableVars_CUDA

    USE cudafor
    USE MOD_ConstVars_CUDA

    USE MOD_LandPatch, only: numpatch
    USE MOD_Vars_Global

    USE MOD_Vars_TimeInvariants
    USE MOD_Vars_TimeVariables
    USE MOD_Vars_1DForcing
    USE MOD_Vars_1DFluxes
    USE MOD_Forcing, only: forcmask_pch, glacierss

    IMPLICIT NONE

! NEW Vars-----------------------------------------------------------------
    integer,  allocatable, device :: l_run_mask             (:)
    real(r8), allocatable, device :: l_deltim_phy           (:)
    integer,  allocatable, device :: l_steps_in_one_deltim  (:)

! MOD_PlantHydraulic_CUDA-----------------------------------------------------------------
    real(r8), allocatable, device :: l_amx_hr(:,:)   ! "a" left off diagonal of tridiagonal matrix
    real(r8), allocatable, device :: l_bmx_hr(:,:)   ! "b" diagonal column for tridiagonal matrix
    real(r8), allocatable, device :: l_cmx_hr(:,:)   ! "c" right off diagonal tridiagonal matrix
    real(r8), allocatable, device :: l_rmx_hr(:,:)   ! "r" forcing term of tridiagonal matrix
    real(r8), allocatable, device :: l_drmx_hr(:,:)  ! "dr" forcing term of tridiagonal matrix for d/dxroot(1)
    real(r8), allocatable, device :: l_x(:,:)        ! root water potential from layer 2 to nl_soil
    real(r8), allocatable, device :: l_dx(:,:)       ! derivate of root water potential from layer 2 to nl_soil (dxroot(:)/dxroot(1))
    real(r8), allocatable, device :: l_xroot(:,:)    ! root water potential from layer 2 to nl_soil
    real(r8), allocatable, device :: l_zmm(:,:)      ! layer depth [mm]
    real(r8), allocatable, device :: l_qeroot_nl(:,:)! root water potential from layer 2 to nl_soil

! CoLMMAIN Vars-----------------------------------------------------------------
!-------------------------- Local Variables ----------------------------
    real(r8), allocatable, device :: l_oro(:)    ! ocean(0)/seaice(2)/ flag
    integer, allocatable, device  :: l_is_dry_lake (:)
    real(r8), allocatable, device :: &
        l_calday                 (:) ,&! Julian cal day (1.xx to 365.xx)
        l_endwb                  (:) ,&! water mass at the end of time step
        l_errore                 (:) ,&! energy balance error (Wm-2)
        l_errorw                 (:) ,&! water balance error (mm)
        l_fiold                (:,:) ,&! fraction of ice relative to the total water
        l_w_old                  (:) ,&! liquid water mass of the column at the previous time step (mm)
        l_sabg_soil              (:) ,&! solar absorbed by soil fraction
        l_sabg_snow              (:) ,&! solar absorbed by snow fraction
        l_parsun                 (:) ,&! PAR by sunlit leaves [W/m2]
        l_parsha                 (:) ,&! PAR by shaded leaves [W/m2]
        l_qseva                  (:) ,&! ground surface evaporation rate (mm h2o/s)
        l_qsdew                  (:) ,&! ground surface dew formation (mm h2o /s) [+]
        l_qsubl                  (:) ,&! sublimation rate from snow pack (mm h2o /s) [+]
        l_qfros                  (:) ,&! surface dew added to snow pack (mm h2o /s) [+]
        l_qseva_soil             (:) ,&! ground soil surface evaporation rate (mm h2o/s)
        l_qsdew_soil             (:) ,&! ground soil surface dew formation (mm h2o /s) [+]
        l_qsubl_soil             (:) ,&! sublimation rate from soil ice pack (mm h2o /s) [+]
        l_qfros_soil             (:) ,&! surface dew added to soil ice pack (mm h2o /s) [+]
        l_qseva_snow             (:) ,&! ground snow surface evaporation rate (mm h2o/s)
        l_qsdew_snow             (:) ,&! ground snow surface dew formation (mm h2o /s) [+]
        l_qsubl_snow             (:) ,&! sublimation rate from snow pack (mm h2o /s) [+]
        l_qfros_snow             (:) ,&! surface dew added to snow pack (mm h2o /s) [+]
        l_scvold                 (:) ,&! snow cover for previous time step [mm]
        l_sm                     (:) ,&! rate of snowmelt [kg/(m2 s)]
        l_ssw                    (:) ,&! water volumetric content of soil surface layer [m3/m3]
        l_tssub                (:,:) ,&! surface/sub-surface temperatures [K]
        l_tssea                  (:) ,&! sea surface temperature [K]
        l_totwb                  (:) ,&! water mass at the beginning of time step
        l_wt                     (:) ,&! fraction of vegetation buried (covered) by snow [-]
        l_z_soisno             (:,:) ,&! layer depth (m)
        l_dz_soisno            (:,:) ,&! layer thickness (m)
        l_zi_soisno            (:,:)  ! interface level below a "z" level (m)
    real(r8), allocatable, device :: &
        l_prc_rain               (:) ,&! convective rainfall [kg/(m2 s)]
        l_prc_snow               (:) ,&! convective snowfall [kg/(m2 s)]
        l_prl_rain               (:) ,&! large scale rainfall [kg/(m2 s)]
        l_prl_snow               (:) ,&! large scale snowfall [kg/(m2 s)]
        l_t_precip               (:) ,&! snowfall/rainfall temperature [kelvin]
        l_bifall                 (:) ,&! bulk density of newly fallen dry snow [kg/m3]
        l_pg_rain                (:) ,&! rainfall onto ground including canopy runoff [kg/(m2 s)]
        l_pg_snow                (:) ,&! snowfall onto ground including canopy runoff [kg/(m2 s)]
        l_qintr_rain             (:) ,&! rainfall interception (mm h2o/s)
        l_qintr_snow             (:)   ! snowfall interception (mm h2o/s)
    integer, allocatable, device :: &
        l_snl                    (:) ,&! number of snow layers
        l_imelt                (:,:) ,&! flag for: melting=1, freezing=2, Nothing happened=0
        l_lb                     (:) ,&! lower bound of arrays
        l_lbsn                     (:) ,&! lower bound of arrays
        l_j                      (:)   ! do looping index
    ! For SNICAR snow model
    !----------------------------------------------------------------------
    integer, allocatable, device  :: l_snl_bef          (:)  !number of snow layers
    real(r8), allocatable, device :: l_forc_aer       (:,:)  !aerosol deposition from atmosphere model (grd,aer) [kg m-1 s-1]
    real(r8), allocatable, device :: l_snofrz         (:,:)  !snow freezing rate (col,lyr) [kg m-2 s-1]
    real(r8), allocatable, device :: l_t_soisno_      (:,:)  !soil + snow layer temperature [K]
    real(r8), allocatable, device :: l_dz_soisno_     (:,:)  !layer thickness (m)
    real(r8), allocatable, device :: l_sabg_snow_lyr  (:,:)  !snow layer absorption [W/m-2]
    !----------------------------------------------------------------------
    real(r8), allocatable, device :: l_a                (:)
    real(r8), allocatable, device :: l_aa               (:)
    real(r8), allocatable, device :: l_gwat             (:)
    real(r8), allocatable, device :: l_wextra           (:)
    real(r8), allocatable, device :: l_t_rain           (:)
    real(r8), allocatable, device :: l_t_snow           (:)

CONTAINS

    SUBROUTINE allocate_var_init (oro)

    IMPLICIT NONE

    real(r8), intent(inout) :: oro(numpatch)  ! ocean(0)/seaice(2)/ flag

    ! NEW Vars-----------------------------------------------------------------
        allocate(l_run_mask              (numpatch)) ; l_run_mask = 0
        allocate(l_deltim_phy            (numpatch))
        allocate(l_steps_in_one_deltim   (numpatch)) ; l_steps_in_one_deltim = 1

    !-------------------------- Local Variables ----------------------------
        allocate(l_amx_hr       (nl_soil,numpatch))
        allocate(l_bmx_hr       (nl_soil,numpatch))
        allocate(l_cmx_hr       (nl_soil,numpatch))
        allocate(l_rmx_hr       (nl_soil,numpatch))
        allocate(l_drmx_hr      (nl_soil-1,numpatch))
        allocate(l_x            (nl_soil,numpatch))
        allocate(l_dx           (nl_soil-1,numpatch))
        allocate(l_xroot          (nl_soil,numpatch))
        allocate(l_zmm          (1:nl_soil,numpatch))
        allocate(l_qeroot_nl    (1:nl_soil,numpatch))

        allocate(l_oro                    (numpatch)) ; l_oro(:) = oro(:)
        allocate(l_is_dry_lake            (numpatch)) ; l_is_dry_lake = 0
        allocate(l_calday                 (numpatch))
        allocate(l_endwb                  (numpatch))
        allocate(l_errore                 (numpatch))
        allocate(l_errorw                 (numpatch))
        allocate(l_fiold    (maxsnl+1:nl_soil,numpatch))
        allocate(l_w_old                  (numpatch))
        allocate(l_sabg_soil              (numpatch))
        allocate(l_sabg_snow              (numpatch))
        allocate(l_parsun                 (numpatch))
        allocate(l_parsha                 (numpatch))
        allocate(l_qseva                  (numpatch))
        allocate(l_qsdew                  (numpatch))
        allocate(l_qsubl                  (numpatch))
        allocate(l_qfros                  (numpatch))
        allocate(l_qseva_soil             (numpatch))
        allocate(l_qsdew_soil             (numpatch))
        allocate(l_qsubl_soil             (numpatch))
        allocate(l_qfros_soil             (numpatch))
        allocate(l_qseva_snow             (numpatch))
        allocate(l_qsdew_snow             (numpatch))
        allocate(l_qsubl_snow             (numpatch))
        allocate(l_qfros_snow             (numpatch))
        allocate(l_scvold                 (numpatch))
        allocate(l_sm                     (numpatch))
        allocate(l_ssw                    (numpatch))
        allocate(l_tssub                   (7,numpatch))
        allocate(l_tssea                  (numpatch))
        allocate(l_totwb                  (numpatch))
        allocate(l_wt                     (numpatch))
        allocate(l_z_soisno (maxsnl+1:nl_soil,numpatch))
        allocate(l_dz_soisno(maxsnl+1:nl_soil,numpatch))
        allocate(l_zi_soisno  (maxsnl:nl_soil,numpatch))
        allocate(l_prc_rain               (numpatch))
        allocate(l_prc_snow               (numpatch))
        allocate(l_prl_rain               (numpatch))
        allocate(l_prl_snow               (numpatch))
        allocate(l_t_precip               (numpatch))
        allocate(l_bifall                 (numpatch))
        allocate(l_pg_rain                (numpatch))
        allocate(l_pg_snow                (numpatch))
        allocate(l_qintr_rain             (numpatch))
        allocate(l_qintr_snow             (numpatch))
        allocate(l_snl                    (numpatch))
        allocate(l_imelt    (maxsnl+1:nl_soil,numpatch))
        allocate(l_lb                     (numpatch))
        allocate(l_lbsn                     (numpatch))
        allocate(l_j                      (numpatch))
        ! For SNICAR snow model
        !----------------------------------------------------------------------
        allocate(l_snl_bef                   (numpatch))
        allocate(l_forc_aer               (14,numpatch))
        allocate(l_snofrz         (maxsnl+1:0,numpatch))
        allocate(l_t_soisno_      (maxsnl+1:1,numpatch))
        allocate(l_dz_soisno_     (maxsnl+1:1,numpatch))
        allocate(l_sabg_snow_lyr  (maxsnl+1:1,numpatch))
        !----------------------------------------------------------------------
        allocate(l_a                (numpatch))
        allocate(l_aa               (numpatch))
        allocate(l_gwat             (numpatch))
        allocate(l_wextra           (numpatch))
        allocate(l_t_rain           (numpatch))
        allocate(l_t_snow           (numpatch))

    END SUBROUTINE allocate_var_init

    SUBROUTINE allocate_var_deinit

    ! NEW Vars-----------------------------------------------------------------
        deallocate(l_run_mask               )
        deallocate(l_deltim_phy             )
        deallocate(l_steps_in_one_deltim    )

    !-------------------------- Local Variables ----------------------------
        deallocate(l_amx_hr                 )
        deallocate(l_bmx_hr                 )
        deallocate(l_cmx_hr                 )
        deallocate(l_rmx_hr                 )
        deallocate(l_drmx_hr                )
        deallocate(l_x                      )
        deallocate(l_dx                     )
        deallocate(l_xroot                  )
        deallocate(l_zmm                    )
        deallocate(l_qeroot_nl              )

        deallocate(l_oro                    )
        deallocate(l_is_dry_lake            )
        deallocate(l_calday                 )
        deallocate(l_endwb                  )
        deallocate(l_errore                 )
        deallocate(l_errorw                 )
        deallocate(l_fiold                  )
        deallocate(l_w_old                  )
        deallocate(l_sabg_soil              )
        deallocate(l_sabg_snow              )
        deallocate(l_parsun                 )
        deallocate(l_parsha                 )
        deallocate(l_qseva                  )
        deallocate(l_qsdew                  )
        deallocate(l_qsubl                  )
        deallocate(l_qfros                  )
        deallocate(l_qseva_soil             )
        deallocate(l_qsdew_soil             )
        deallocate(l_qsubl_soil             )
        deallocate(l_qfros_soil             )
        deallocate(l_qseva_snow             )
        deallocate(l_qsdew_snow             )
        deallocate(l_qsubl_snow             )
        deallocate(l_qfros_snow             )
        deallocate(l_scvold                 )
        deallocate(l_sm                     )
        deallocate(l_ssw                    )
        deallocate(l_tssub                  )
        deallocate(l_tssea                  )
        deallocate(l_totwb                  )
        deallocate(l_wt                     )
        deallocate(l_z_soisno               )
        deallocate(l_dz_soisno              )
        deallocate(l_zi_soisno              )
        deallocate(l_prc_rain               )
        deallocate(l_prc_snow               )
        deallocate(l_prl_rain               )
        deallocate(l_prl_snow               )
        deallocate(l_t_precip               )
        deallocate(l_bifall                 )
        deallocate(l_pg_rain                )
        deallocate(l_pg_snow                )
        deallocate(l_qintr_rain             )
        deallocate(l_qintr_snow             )
        deallocate(l_snl                    )
        deallocate(l_imelt                  )
        deallocate(l_lb                     )
        deallocate(l_lbsn                    )
        deallocate(l_j                      )
        ! For SNICAR snow model
        !----------------------------------------------------------------------
        deallocate(l_snl_bef                )
        deallocate(l_forc_aer               )
        deallocate(l_snofrz                 )
        deallocate(l_t_soisno_              )
        deallocate(l_dz_soisno_             )
        deallocate(l_sabg_snow_lyr          )
        !----------------------------------------------------------------------
        deallocate(l_a                      )
        deallocate(l_aa                     )
        deallocate(l_gwat                   )
        deallocate(l_wextra                 )
        deallocate(l_t_rain                 )
        deallocate(l_t_snow                 )

    END SUBROUTINE allocate_var_deinit

END MODULE MOD_AllocatableVars_CUDA