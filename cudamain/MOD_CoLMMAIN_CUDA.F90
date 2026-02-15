#include <define.h>

MODULE MOD_CoLMMAIN_CUDA
!-----------------------------------------------------------------------
! CUDA Fortran 数据管理模块
! 
! 功能：
!   1. GPU设备初始化和管理
!   2. 数据预取优化（使用统一内存）
!   3. 为GPU核函数提供接口
!
! 编译选项要求：
!   -cuda -gpu=mem:unified
!
! Created: 2026/01
!-----------------------------------------------------------------------

    USE cudafor
    USE MOD_Precision
    USE MOD_Vars_Global

    IMPLICIT NONE
    
    integer,  constant :: d_idate(3)

    real(r8), constant :: d_deltim
    logical,  constant :: d_dolai
    logical,  constant :: d_doalb
    logical,  constant :: d_dosst

    real(r8), constant :: d_zlnd                             !roughness length for soil [m]
    real(r8), constant :: d_zsno                             !roughness length for snow [m]
    real(r8), constant :: d_csoilc                           !drag coefficient for soil under canopy [-]
    real(r8), constant :: d_dewmx                            !maximum dew
    
    real(r8), constant :: d_capr                             !tuning factor to turn first layer T into surface T
    real(r8), constant :: d_cnfac                            !Crank Nicholson factor between 0 and 1
    real(r8), constant :: d_ssi                              !irreducible water saturation of snow
    real(r8), constant :: d_wimp                             !water impremeable IF porosity less than wimp
    real(r8), constant :: d_pondmx                           !ponding depth (mm)
    real(r8), constant :: d_smpmax                           !wilting point potential in mm
    real(r8), constant :: d_smpmin                           !restriction for min of soil poten. (mm)
    real(r8), constant :: d_trsmx0                           !max transpiration for moist soil+100% veg.  [mm/s]
    real(r8), constant :: d_tcrit                            !critical temp. to determine rain or snow
    real(r8), constant :: d_wetwatmax                        !maximum wetland water (mm)

    real(r8), constant :: d_z_soi (1:nl_soil)
    real(r8), constant :: d_dz_soi(1:nl_soil)

    logical,  constant :: d_DEF_forcing_has_missing_value
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
    logical,  constant :: d_def_use_supercool_water
    logical,  constant :: d_DEF_URBAN_RUN
    logical,  constant :: d_DEF_Aerosol_Clim

    integer,  constant :: d_DEF_Interception_scheme
    integer,  constant :: d_DEF_precip_phase_discrimination_scheme
    integer,  constant :: d_DEF_RSS_SCHEME
    integer,  constant :: d_DEF_HEIGHT_mode
    integer,  constant :: d_DEF_THERMAL_CONDUCTIVITY_SCHEME
    integer,  constant :: d_DEF_Runoff_SCHEME
    integer,  constant :: d_p_iam_glb

    real(r8), constant :: d_DEF_simulation_time_timestep
    
    character(len=256), constant :: d_DEF_dir_runtime
    
    real(r8), dimension(N_land_classification), constant :: &
        d_patchtypes, &! land patch types
        d_htop0,      &! canopy top height
        d_hbot0,      &! canopy bottom height
        d_fveg0,      &! canopy vegetation fractional cover
        d_sai0,       &! canopy stem area index
        d_chil,       &! leaf angle distribution factor
        d_z0mr,       &! ratio to calculate roughness length z0m
        d_displar,    &! ratio to calculate displacement height d
        d_sqrtdi,     &! inverse sqrt of leaf dimension [m**-0.5]

        d_vmax25,     &! maximum carboxylation rate at 25 C at canopy top
        d_effcon,     &! quantum efficiency
        d_g1,         &! conductance-photosynthesis slope parameter
        d_g0,         &! conductance-photosynthesis intercept
        d_gradm,      &! conductance-photosynthesis slope parameter
        d_binter,     &! conductance-photosynthesis intercept
        d_respcp,     &! respiration fraction
        d_shti,       &! slope of high temperature inhibition function (s1)
        d_slti,       &! slope of low temperature inhibition function (s3)
        d_trda,       &! temperature coefficient in gs-a model (s5)
        d_trdm,       &! temperature coefficient in gs-a model (s6)
        d_trop,       &! temperature coefficient in gs-a model (273.16+25)
        d_hhti,       &! 1/2 point of high temperature inhibition function (s2)
        d_hlti,       &! 1/2 point of low temperature inhibition function (s4)
        d_extkn,      &! coefficient of leaf nitrogen allocation

        d_lambda,     &! marginal water cost of carbon gain (mol mol-1)

        d_d50,        &! depth at 50% roots
        d_beta         ! coefficient of root profile

    ! Plant Hydraulic Parameters
    real(r8), dimension(N_land_classification), constant :: &
        d_kmax_sun,   &! Plant Hydraulics Paramters (TODO@Xingjie Lu, please give more details and below)
        d_kmax_sha,   &! Plant Hydraulics Paramters
        d_kmax_xyl,   &! Plant Hydraulics Paramters
        d_kmax_root,  &! Plant Hydraulics Paramters
        d_psi50_sun,  &! water potential at 50% loss of sunlit leaf tissue conductance (mmH2O)
        d_psi50_sha,  &! water potential at 50% loss of shaded leaf tissue conductance (mmH2O)
        d_psi50_xyl,  &! water potential at 50% loss of xylem tissue conductance (mmH2O)
        d_psi50_root, &! water potential at 50% loss of root tissue conductance (mmH2O)
        d_ck           ! shape-fitting parameter for vulnerability curve (-)
    ! end plant hydraulic parameters

    ! fraction of roots in each soil layer
    real(r8), dimension(nl_soil,N_land_classification), constant :: d_rootfr

    real(r8), constant :: d_rho(2,2,N_land_classification)
    real(r8), constant :: d_tau(2,2,N_land_classification)

    ! GPU设备信息
    integer, save :: gpu_device_id = 0           ! 当前使用的GPU设备ID
    integer, save :: gpu_device_stream = 0       ! 当前使用的GPU设备流ID
    integer, save :: gpu_device_count = 0        ! 系统中GPU设备数量
    logical, save :: gpu_initialized = .false.   ! GPU是否已初始化
    
    ! GPU执行配置
    integer, save :: default_block_size = 256    ! 默认线程块大小
    
    ! 设备属性
    type(cudaDeviceProp), save :: gpu_prop       ! GPU设备属性

    ! PUBLIC MEMBER FUNCTIONS:
    PUBLIC :: init_GPU
    PUBLIC :: finalize_GPU
    PUBLIC :: calculate_grid_config
    PUBLIC :: prefetch_Vars_to_GPU
    PUBLIC :: prefetch_Fluxes_to_CPU
    PUBLIC :: sync_GPU

!-----------------------------------------------------------------------
CONTAINS
!-----------------------------------------------------------------------

    SUBROUTINE init_GPU(device_id)
    !--------------------------------------------------------------------
    ! 初始化GPU设备
    ! 
    ! 参数：
    !   device_id - 可选，指定使用的GPU设备ID，默认为0
    !--------------------------------------------------------------------
        integer, intent(in), optional :: device_id
        
        integer :: istat
        integer :: dev_id
        
        ! 确定设备ID
        IF (present(device_id)) THEN
            dev_id = device_id
        ELSE
            dev_id = 0
        ENDIF
        
        ! 获取GPU设备数量
        istat = cudaGetDeviceCount(gpu_device_count)
        IF (istat /= cudaSuccess) THEN
            write(*,*) 'Error: cudaGetDeviceCount failed!'
            write(*,*) 'CUDA Error: ', cudaGetErrorString(istat)
            RETURN
        ENDIF
        
        IF (gpu_device_count == 0) THEN
            write(*,*) 'Warning: No CUDA-capable GPU detected!'
            RETURN
        ENDIF
        
        ! 检查设备ID是否有效
        IF (dev_id >= gpu_device_count) THEN
            write(*,*) 'Warning: Invalid device ID, using device 0'
            dev_id = 0
        ENDIF
        
        ! 设置当前设备
        istat = cudaSetDevice(dev_id)
        IF (istat /= cudaSuccess) THEN
            write(*,*) 'Error: cudaSetDevice failed!'
            write(*,*) 'CUDA Error: ', cudaGetErrorString(istat)
            RETURN
        ENDIF
        
        gpu_device_id = dev_id
        
        ! 获取设备属性
        istat = cudaGetDeviceProperties(gpu_prop, gpu_device_id)
        IF (istat /= cudaSuccess) THEN
            write(*,*) 'Error: cudaGetDeviceProperties failed!'
            RETURN
        ENDIF
        
        gpu_initialized = .true.
        
        ! 打印GPU信息
        CALL get_GPU_info()
        
        CALL constant_init()
        
    END SUBROUTINE init_GPU

    !-----------------------------------------------------------------------

    SUBROUTINE finalize_GPU()
    !--------------------------------------------------------------------
    ! 清理GPU资源
    !--------------------------------------------------------------------
        integer :: istat
        
        IF (gpu_initialized) THEN
            istat = cudaDeviceReset()
            gpu_initialized = .false.
        ENDIF
        
    END SUBROUTINE finalize_GPU

    !-----------------------------------------------------------------------

    SUBROUTINE get_GPU_info()
    !--------------------------------------------------------------------
    ! 打印GPU设备信息
    !--------------------------------------------------------------------
        
        IF (.not. gpu_initialized) THEN
            write(*,*) 'GPU not initialized!'
            RETURN
        ENDIF
        
        write(*,*) '================================================'
        write(*,*) 'GPU Device Information:'
        write(*,*) '================================================'
        write(*,*) 'Device ID:              ', gpu_device_id
        write(*,*) 'Device Name:            ', trim(gpu_prop%name)
        write(*,*) 'Compute Capability:     ', gpu_prop%major, '.', gpu_prop%minor
        write(*,*) 'Total Global Memory:    ', gpu_prop%totalGlobalMem / (1024*1024), ' MB'
        write(*,*) 'Shared Memory per Block:', gpu_prop%sharedMemPerBlock / 1024, ' KB'
        write(*,*) 'Max Threads per Block:  ', gpu_prop%maxThreadsPerBlock
        write(*,*) 'Max Grid Size:          ', gpu_prop%maxGridSize(1), 'x', &
                                                gpu_prop%maxGridSize(2), 'x', &
                                                gpu_prop%maxGridSize(3)
        write(*,*) 'Warp Size:              ', gpu_prop%warpSize
        write(*,*) 'Multi-Processor Count:  ', gpu_prop%multiProcessorCount
        write(*,*) 'Unified Addressing:     ', gpu_prop%unifiedAddressing
        write(*,*) 'Managed Memory:         ', gpu_prop%managedMemory
        write(*,*) '================================================'
        
    END SUBROUTINE get_GPU_info

    !-----------------------------------------------------------------------

    SUBROUTINE calculate_grid_config(n_elements, block_size, grid_size)
    !--------------------------------------------------------------------
    ! 计算GPU执行的网格配置
    !
    ! 参数：
    !   n_elements - 需要处理的元素数量
    !   block_size - 输出，每个block的线程数
    !   grid_size  - 输出，grid中block的数量
    !--------------------------------------------------------------------
        integer, intent(in)  :: n_elements
        integer, intent(out) :: block_size
        integer, intent(out) :: grid_size
        
        block_size = default_block_size
        grid_size = (n_elements + block_size - 1) / block_size
        
        ! 确保不超过GPU限制
        IF (gpu_initialized) THEN
            IF (block_size > gpu_prop%maxThreadsPerBlock) THEN
                block_size = gpu_prop%maxThreadsPerBlock
                grid_size = (n_elements + block_size - 1) / block_size
            ENDIF
        ENDIF
        
    END SUBROUTINE calculate_grid_config

    !-----------------------------------------------------------------------

    SUBROUTINE sync_GPU()
    !--------------------------------------------------------------------
    ! 同步GPU，等待所有GPU操作完成
    !--------------------------------------------------------------------
        integer :: istat
        
        istat = cudaDeviceSynchronize()
        IF (istat /= cudaSuccess) THEN
            write(*,*) 'Warning: cudaDeviceSynchronize failed!'
            write(*,*) 'CUDA Error: ', cudaGetErrorString(istat)
        ENDIF
        
    END SUBROUTINE sync_GPU

    !-----------------------------------------------------------------------

    SUBROUTINE constant_init()

        USE MOD_Const_Physical, only: tfrz, rgas, vonkar, denh2o, denice, cpliq, cpice
        USE MOD_Const_LC
        USE MOD_SPMD_Task
        USE MOD_TimeManager
        USE MOD_UserSpecifiedForcing, only: HEIGHT_mode
        USE MOD_Vars_TimeInvariants
        USE MOD_Vars_TimeVariables

        d_DEF_forcing_has_missing_value = DEF_forcing%has_missing_value
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
        
        d_DEF_simulation_time_timestep = DEF_simulation_time%timestep

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

        ! TUNABLE modle constants
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
        
        d_patchtypes = patchtypes
        d_htop0      = htop0
        d_hbot0      = hbot0
        d_fveg0      = fveg0
        d_sai0       = sai0
        d_chil       = chil
        d_z0mr       = z0mr
        d_displar    = displar
        d_sqrtdi     = sqrtdi
        d_vmax25     = vmax25
        d_effcon     = effcon
        d_g1         = g1
        d_g0         = g0
        d_gradm      = gradm
        d_binter     = binter
        d_respcp     = respcp
        d_shti       = shti
        d_slti       = slti
        d_trda       = trda
        d_trdm       = trdm
        d_trop       = trop
        d_hhti       = hhti
        d_hlti       = hlti
        d_extkn      = extkn
        d_lambda     = lambda
        d_d50        = d50
        d_beta       = beta

        d_kmax_sun   = kmax_sun
        d_kmax_sha   = kmax_sha
        d_kmax_xyl   = kmax_xyl
        d_kmax_root  = kmax_root
        d_psi50_sun  = psi50_sun
        d_psi50_sha  = psi50_sha
        d_psi50_xyl  = psi50_xyl
        d_psi50_root = psi50_root
        d_ck         = ck

        d_rootfr     = rootfr
        
        d_rho = rho
        d_tau = tau

        write(*,*) 'constant init done'

    END SUBROUTINE constant_init

    !-----------------------------------------------------------------------

    SUBROUTINE prefetch_Vars_to_GPU(numpatch)
    !--------------------------------------------------------------------
    ! 预取变量数据到GPU
    ! 
    ! 使用统一内存时，数据会在首次访问时自动迁移。
    ! 预取可以提前触发迁移，减少核函数执行时的延迟。
    !
    ! 参数：
    !   numpatch - patch数量
    !--------------------------------------------------------------------
        USE MOD_Vars_TimeInvariants
        USE MOD_Vars_TimeVariables
        USE MOD_Vars_1DForcing
        USE MOD_Vars_1DFluxes
        
        integer, intent(in) :: numpatch
        integer :: istat
        
        IF (.not. gpu_initialized) RETURN
        
        istat = cudaMemPrefetchAsync(coszen, sizeof(coszen), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(patchlonr, sizeof(patchlonr), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(patchlatr, sizeof(patchlatr), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(patchclass, sizeof(patchclass), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(patchtype, sizeof(patchtype), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(soil_s_v_alb, sizeof(soil_s_v_alb), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(soil_d_v_alb, sizeof(soil_d_v_alb), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(soil_s_n_alb, sizeof(soil_s_n_alb), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(soil_d_n_alb, sizeof(soil_d_n_alb), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(vf_quartz, sizeof(vf_quartz), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(vf_gravels, sizeof(vf_gravels), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(vf_om, sizeof(vf_om), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(vf_sand, sizeof(vf_sand), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(wf_gravels, sizeof(wf_gravels), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(wf_sand, sizeof(wf_sand), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(porsl, sizeof(porsl), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(psi0, sizeof(psi0), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(bsw, sizeof(bsw), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(theta_r, sizeof(theta_r), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fsatmax, sizeof(fsatmax), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fsatdcf, sizeof(fsatdcf), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(hksati, sizeof(hksati), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(csol, sizeof(csol), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(k_solids, sizeof(k_solids), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(dksatu, sizeof(dksatu), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(dksatf, sizeof(dksatf), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(dkdry, sizeof(dkdry), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(BA_alpha, sizeof(BA_alpha), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(BA_beta, sizeof(BA_beta), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(lakedepth, sizeof(lakedepth), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(dz_lake, sizeof(dz_lake), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(elvstd, sizeof(elvstd), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(BVIC, sizeof(BVIC), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(htop, sizeof(htop), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(hbot, sizeof(hbot), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(forc_pco2m, sizeof(forc_pco2m), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_po2m, sizeof(forc_po2m), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_us, sizeof(forc_us), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_vs, sizeof(forc_vs), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_t, sizeof(forc_t), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_q, sizeof(forc_q), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_prc, sizeof(forc_prc), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_prl, sizeof(forc_prl), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_rain, sizeof(forc_rain), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_snow, sizeof(forc_snow), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_psrf, sizeof(forc_psrf), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_pbot, sizeof(forc_pbot), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_sols, sizeof(forc_sols), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_soll, sizeof(forc_soll), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_solsd, sizeof(forc_solsd), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_solld, sizeof(forc_solld), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_frl, sizeof(forc_frl), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_hgt_u, sizeof(forc_hgt_u), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_hgt_t, sizeof(forc_hgt_t), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_hgt_q, sizeof(forc_hgt_q), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_rhoair, sizeof(forc_rhoair), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(forc_hpbl, sizeof(forc_hpbl), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(z_sno, sizeof(z_sno), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(dz_sno, sizeof(dz_sno), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(t_soisno, sizeof(t_soisno), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(wliq_soisno, sizeof(wliq_soisno), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(wice_soisno, sizeof(wice_soisno), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(smp, sizeof(smp), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(hk, sizeof(hk), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(t_grnd, sizeof(t_grnd), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(tleaf, sizeof(tleaf), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(ldew, sizeof(ldew), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(ldew_rain, sizeof(ldew_rain), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(ldew_snow, sizeof(ldew_snow), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fwet_snow, sizeof(fwet_snow), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(sag, sizeof(sag), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(scv, sizeof(scv), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(snowdp, sizeof(snowdp), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fveg, sizeof(fveg), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fsno, sizeof(fsno), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(sigf, sizeof(sigf), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(green, sizeof(green), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(lai, sizeof(lai), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(sai, sizeof(sai), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(alb, sizeof(alb), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(ssun, sizeof(ssun), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(ssha, sizeof(ssha), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(ssoi, sizeof(ssoi), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(ssno, sizeof(ssno), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(thermk, sizeof(thermk), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(extkb, sizeof(extkb), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(extkd, sizeof(extkd), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(vegwp, sizeof(vegwp), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(gs0sun, sizeof(gs0sun), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(gs0sha, sizeof(gs0sha), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(lai_old, sizeof(lai_old), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(o3uptakesun, sizeof(o3uptakesun), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(o3uptakesha, sizeof(o3uptakesha), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(forc_ozone, sizeof(forc_ozone), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(zwt, sizeof(zwt), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(wdsrf, sizeof(wdsrf), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(wa, sizeof(wa), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(wetwat, sizeof(wetwat), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(t_lake, sizeof(t_lake), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(lake_icefrac, sizeof(lake_icefrac), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(savedtke1, sizeof(savedtke1), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(snw_rds, sizeof(snw_rds), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(ssno_lyr, sizeof(ssno_lyr), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(mss_bcpho, sizeof(mss_bcpho), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(mss_bcphi, sizeof(mss_bcphi), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(mss_ocpho, sizeof(mss_ocpho), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(mss_ocphi, sizeof(mss_ocphi), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(mss_dst1, sizeof(mss_dst1), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(mss_dst2, sizeof(mss_dst2), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(mss_dst3, sizeof(mss_dst3), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(mss_dst4, sizeof(mss_dst4), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(laisun, sizeof(laisun), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(laisha, sizeof(laisha), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rootr, sizeof(rootr), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rootflux, sizeof(rootflux), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rss, sizeof(rss), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rstfacsun_out, sizeof(rstfacsun_out), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rstfacsha_out, sizeof(rstfacsha_out), gpu_device_id, gpu_device_stream)

        istat = cudaMemPrefetchAsync(gssun_out, sizeof(gssun_out), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(gssha_out, sizeof(gssha_out), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(assimsun_out, sizeof(assimsun_out), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(etrsun_out, sizeof(etrsun_out), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(assimsha_out, sizeof(assimsha_out), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(etrsha_out, sizeof(etrsha_out), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(h2osoi, sizeof(h2osoi), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(wat, sizeof(wat), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(taux, sizeof(taux), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(tauy, sizeof(tauy), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fsena, sizeof(fsena), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fevpa, sizeof(fevpa), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(lfevpa, sizeof(lfevpa), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fsenl, sizeof(fsenl), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fevpl, sizeof(fevpl), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(etr, sizeof(etr), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(fseng, sizeof(fseng), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fevpg, sizeof(fevpg), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(olrg, sizeof(olrg), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fgrnd, sizeof(fgrnd), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(trad, sizeof(trad), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(tref, sizeof(tref), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(qref, sizeof(qref), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rsur, sizeof(rsur), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rsur_se, sizeof(rsur_se), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rsur_ie, sizeof(rsur_ie), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rnof, sizeof(rnof), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(qintr, sizeof(qintr), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(qinfl, sizeof(qinfl), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(qdrip, sizeof(qdrip), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rst, sizeof(rst), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(assim, sizeof(assim), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(respc, sizeof(respc), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(sabvsun, sizeof(sabvsun), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(sabvsha, sizeof(sabvsha), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(sabg, sizeof(sabg), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(sr, sizeof(sr), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(solvd, sizeof(solvd), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(solvi, sizeof(solvi), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(solnd, sizeof(solnd), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(solni, sizeof(solni), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(srvd, sizeof(srvd), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(srvi, sizeof(srvi), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(srnd, sizeof(srnd), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(srni, sizeof(srni), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(solvdln, sizeof(solvdln), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(solviln, sizeof(solviln), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(solndln, sizeof(solndln), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(solniln, sizeof(solniln), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(srvdln, sizeof(srvdln), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(srviln, sizeof(srviln), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(srndln, sizeof(srndln), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(srniln, sizeof(srniln), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(qcharge, sizeof(qcharge), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(xerr, sizeof(xerr), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(zerr, sizeof(zerr), gpu_device_id, gpu_device_stream)
        
        istat = cudaMemPrefetchAsync(emis, sizeof(emis), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(z0m, sizeof(z0m), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(zol, sizeof(zol), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(rib, sizeof(rib), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(ustar, sizeof(ustar), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(qstar, sizeof(qstar), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(tstar, sizeof(tstar), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fm, sizeof(fm), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fh, sizeof(fh), gpu_device_id, gpu_device_stream)
        istat = cudaMemPrefetchAsync(fq, sizeof(fq), gpu_device_id, gpu_device_stream)

        write(*,*) 'prefetch Variables to GPU done'
        
    END SUBROUTINE prefetch_Vars_to_GPU

    !-----------------------------------------------------------------------

    SUBROUTINE prefetch_Fluxes_to_CPU(numpatch)
    !--------------------------------------------------------------------
    ! 预取通量输出数据回CPU
    ! 
    ! GPU计算完成后，将结果预取回CPU以便后续处理和输出
    !
    ! 参数：
    !   numpatch - patch数量
    !--------------------------------------------------------------------
        USE MOD_Vars_1DFluxes
        USE MOD_Vars_TimeVariables, only: tref, qref, trad, emis, z0m, &
                                            zol, rib, ustar, qstar, tstar, &
                                            fm, fh, fq, t_grnd, tleaf
        
        integer, intent(in) :: numpatch
        integer :: istat
        integer(8) :: nbytes
        integer, parameter :: cudaCpuDeviceId = -1  ! CPU设备ID
        
        IF (.not. gpu_initialized) RETURN
        
        ! 预取动量通量
        nbytes = sizeof(taux)
        istat = cudaMemPrefetchAsync(taux, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(tauy)
        istat = cudaMemPrefetchAsync(tauy, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取感热通量
        nbytes = sizeof(fsena)
        istat = cudaMemPrefetchAsync(fsena, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(fseng)
        istat = cudaMemPrefetchAsync(fseng, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(fsenl)
        istat = cudaMemPrefetchAsync(fsenl, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取潜热通量
        nbytes = sizeof(fevpa)
        istat = cudaMemPrefetchAsync(fevpa, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(fevpg)
        istat = cudaMemPrefetchAsync(fevpg, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(fevpl)
        istat = cudaMemPrefetchAsync(fevpl, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(lfevpa)
        istat = cudaMemPrefetchAsync(lfevpa, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取蒸散发
        nbytes = sizeof(etr)
        istat = cudaMemPrefetchAsync(etr, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取长波辐射
        nbytes = sizeof(olrg)
        istat = cudaMemPrefetchAsync(olrg, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取地表热通量
        nbytes = sizeof(fgrnd)
        istat = cudaMemPrefetchAsync(fgrnd, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取径流
        nbytes = sizeof(rsur)
        istat = cudaMemPrefetchAsync(rsur, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(rnof)
        istat = cudaMemPrefetchAsync(rnof, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取入渗
        nbytes = sizeof(qinfl)
        istat = cudaMemPrefetchAsync(qinfl, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取截留
        nbytes = sizeof(qintr)
        istat = cudaMemPrefetchAsync(qintr, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取穿透降水
        nbytes = sizeof(qdrip)
        istat = cudaMemPrefetchAsync(qdrip, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取辐射吸收
        nbytes = sizeof(sabvsun)
        istat = cudaMemPrefetchAsync(sabvsun, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(sabvsha)
        istat = cudaMemPrefetchAsync(sabvsha, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(sabg)
        istat = cudaMemPrefetchAsync(sabg, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取诊断变量
        nbytes = sizeof(tref)
        istat = cudaMemPrefetchAsync(tref, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(qref)
        istat = cudaMemPrefetchAsync(qref, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(trad)
        istat = cudaMemPrefetchAsync(trad, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        ! 预取更新后的状态变量
        nbytes = sizeof(t_grnd)
        istat = cudaMemPrefetchAsync(t_grnd, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
        nbytes = sizeof(tleaf)
        istat = cudaMemPrefetchAsync(tleaf, nbytes, cudaCpuDeviceId, gpu_device_stream)
        
    END SUBROUTINE prefetch_Fluxes_to_CPU

!-----------------------------------------------------------------------

END MODULE MOD_CoLMMAIN_CUDA
