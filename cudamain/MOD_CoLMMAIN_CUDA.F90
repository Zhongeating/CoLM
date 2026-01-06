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
   SAVE

   ! GPU设备信息
   integer :: gpu_device_id = 0           ! 当前使用的GPU设备ID
   integer :: gpu_device_stream = 0       ! 当前使用的GPU设备流ID
   integer :: gpu_device_count = 0        ! 系统中GPU设备数量
   logical :: gpu_initialized = .false.   ! GPU是否已初始化
   
   ! GPU执行配置
   integer :: default_block_size = 256    ! 默认线程块大小
   
   ! 设备属性
   type(cudaDeviceProp) :: gpu_prop       ! GPU设备属性

   ! PUBLIC MEMBER FUNCTIONS:
   PUBLIC :: init_GPU
   PUBLIC :: finalize_GPU
   PUBLIC :: get_GPU_info
   PUBLIC :: prefetch_TimeVariables_to_GPU
   PUBLIC :: prefetch_Forcing_to_GPU
   PUBLIC :: prefetch_Fluxes_to_CPU
   PUBLIC :: sync_GPU
   PUBLIC :: calculate_grid_config

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

    SUBROUTINE prefetch_TimeVariables_to_GPU(numpatch)
    !--------------------------------------------------------------------
    ! 预取时间变量数据到GPU
    ! 
    ! 使用统一内存时，数据会在首次访问时自动迁移。
    ! 预取可以提前触发迁移，减少核函数执行时的延迟。
    !
    ! 参数：
    !   numpatch - patch数量
    !--------------------------------------------------------------------
        USE MOD_Vars_TimeVariables
        
        integer, intent(in) :: numpatch
        integer :: istat
        integer(8) :: nbytes
        
        IF (.not. gpu_initialized) RETURN
        
        ! 预取土壤/雪层温度数据
        nbytes = sizeof(t_soisno)
        istat = cudaMemPrefetchAsync(t_soisno, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取土壤/雪层液态水
        nbytes = sizeof(wliq_soisno)
        istat = cudaMemPrefetchAsync(wliq_soisno, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取土壤/雪层冰
        nbytes = sizeof(wice_soisno)
        istat = cudaMemPrefetchAsync(wice_soisno, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取雪层深度
        nbytes = sizeof(z_sno)
        istat = cudaMemPrefetchAsync(z_sno, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(dz_sno)
        istat = cudaMemPrefetchAsync(dz_sno, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取土壤水势
        nbytes = sizeof(smp)
        istat = cudaMemPrefetchAsync(smp, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取水力传导率
        nbytes = sizeof(hk)
        istat = cudaMemPrefetchAsync(hk, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取地表温度
        nbytes = sizeof(t_grnd)
        istat = cudaMemPrefetchAsync(t_grnd, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取叶温
        nbytes = sizeof(tleaf)
        istat = cudaMemPrefetchAsync(tleaf, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取叶面水
        nbytes = sizeof(ldew)
        istat = cudaMemPrefetchAsync(ldew, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取雪盖
        nbytes = sizeof(scv)
        istat = cudaMemPrefetchAsync(scv, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(snowdp)
        istat = cudaMemPrefetchAsync(snowdp, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取植被覆盖
        nbytes = sizeof(fveg)
        istat = cudaMemPrefetchAsync(fveg, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(fsno)
        istat = cudaMemPrefetchAsync(fsno, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取LAI/SAI
        nbytes = sizeof(lai)
        istat = cudaMemPrefetchAsync(lai, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(sai)
        istat = cudaMemPrefetchAsync(sai, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取反照率
        nbytes = sizeof(alb)
        istat = cudaMemPrefetchAsync(alb, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取太阳天顶角余弦
        nbytes = sizeof(coszen)
        istat = cudaMemPrefetchAsync(coszen, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取湖泊温度
        nbytes = sizeof(t_lake)
        istat = cudaMemPrefetchAsync(t_lake, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(lake_icefrac)
        istat = cudaMemPrefetchAsync(lake_icefrac, nbytes, gpu_device_id, gpu_device_stream)
        
    END SUBROUTINE prefetch_TimeVariables_to_GPU

    !-----------------------------------------------------------------------

    SUBROUTINE prefetch_Forcing_to_GPU(numpatch)
    !--------------------------------------------------------------------
    ! 预取强迫数据到GPU
    !
    ! 参数：
    !   numpatch - patch数量
    !--------------------------------------------------------------------
        USE MOD_Vars_1DForcing
        
        integer, intent(in) :: numpatch
        integer :: istat
        integer(8) :: nbytes
        
        IF (.not. gpu_initialized) RETURN
        
        ! 预取温度
        nbytes = sizeof(forc_t)
        istat = cudaMemPrefetchAsync(forc_t, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取比湿
        nbytes = sizeof(forc_q)
        istat = cudaMemPrefetchAsync(forc_q, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取风速
        nbytes = sizeof(forc_us)
        istat = cudaMemPrefetchAsync(forc_us, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(forc_vs)
        istat = cudaMemPrefetchAsync(forc_vs, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取降水
        nbytes = sizeof(forc_prc)
        istat = cudaMemPrefetchAsync(forc_prc, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(forc_prl)
        istat = cudaMemPrefetchAsync(forc_prl, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取辐射
        nbytes = sizeof(forc_sols)
        istat = cudaMemPrefetchAsync(forc_sols, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(forc_soll)
        istat = cudaMemPrefetchAsync(forc_soll, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(forc_solsd)
        istat = cudaMemPrefetchAsync(forc_solsd, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(forc_solld)
        istat = cudaMemPrefetchAsync(forc_solld, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(forc_frl)
        istat = cudaMemPrefetchAsync(forc_frl, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取气压
        nbytes = sizeof(forc_psrf)
        istat = cudaMemPrefetchAsync(forc_psrf, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(forc_pbot)
        istat = cudaMemPrefetchAsync(forc_pbot, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取空气密度
        nbytes = sizeof(forc_rhoair)
        istat = cudaMemPrefetchAsync(forc_rhoair, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取观测高度
        nbytes = sizeof(forc_hgt_u)
        istat = cudaMemPrefetchAsync(forc_hgt_u, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(forc_hgt_t)
        istat = cudaMemPrefetchAsync(forc_hgt_t, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(forc_hgt_q)
        istat = cudaMemPrefetchAsync(forc_hgt_q, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取CO2/O2浓度
        nbytes = sizeof(forc_pco2m)
        istat = cudaMemPrefetchAsync(forc_pco2m, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(forc_po2m)
        istat = cudaMemPrefetchAsync(forc_po2m, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取边界层高度
        nbytes = sizeof(forc_hpbl)
        istat = cudaMemPrefetchAsync(forc_hpbl, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取气溶胶沉降
        nbytes = sizeof(forc_aerdep)
        istat = cudaMemPrefetchAsync(forc_aerdep, nbytes, gpu_device_id, gpu_device_stream)
        
    END SUBROUTINE prefetch_Forcing_to_GPU

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

    SUBROUTINE prefetch_TimeInvariants_to_GPU(numpatch)
    !--------------------------------------------------------------------
    ! 预取时间不变量数据到GPU
    ! 
    ! 这些数据在模拟过程中不变，只需在初始化时预取一次
    !
    ! 参数：
    !   numpatch - patch数量
    !--------------------------------------------------------------------
        USE MOD_Vars_TimeInvariants
        
        integer, intent(in) :: numpatch
        integer :: istat
        integer(8) :: nbytes
        
        IF (.not. gpu_initialized) RETURN
        
        ! 预取土壤参数
        nbytes = sizeof(porsl)
        istat = cudaMemPrefetchAsync(porsl, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(psi0)
        istat = cudaMemPrefetchAsync(psi0, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(bsw)
        istat = cudaMemPrefetchAsync(bsw, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(hksati)
        istat = cudaMemPrefetchAsync(hksati, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(csol)
        istat = cudaMemPrefetchAsync(csol, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(dksatu)
        istat = cudaMemPrefetchAsync(dksatu, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(dksatf)
        istat = cudaMemPrefetchAsync(dksatf, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(dkdry)
        istat = cudaMemPrefetchAsync(dkdry, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取土壤反照率
        nbytes = sizeof(soil_s_v_alb)
        istat = cudaMemPrefetchAsync(soil_s_v_alb, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(soil_d_v_alb)
        istat = cudaMemPrefetchAsync(soil_d_v_alb, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(soil_s_n_alb)
        istat = cudaMemPrefetchAsync(soil_s_n_alb, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(soil_d_n_alb)
        istat = cudaMemPrefetchAsync(soil_d_n_alb, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取patch信息
        nbytes = sizeof(patchclass)
        istat = cudaMemPrefetchAsync(patchclass, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(patchtype)
        istat = cudaMemPrefetchAsync(patchtype, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(patchlonr)
        istat = cudaMemPrefetchAsync(patchlonr, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(patchlatr)
        istat = cudaMemPrefetchAsync(patchlatr, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取植被参数
        nbytes = sizeof(htop)
        istat = cudaMemPrefetchAsync(htop, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(hbot)
        istat = cudaMemPrefetchAsync(hbot, nbytes, gpu_device_id, gpu_device_stream)
        
        ! 预取湖泊深度
        nbytes = sizeof(lakedepth)
        istat = cudaMemPrefetchAsync(lakedepth, nbytes, gpu_device_id, gpu_device_stream)
        
        nbytes = sizeof(dz_lake)
        istat = cudaMemPrefetchAsync(dz_lake, nbytes, gpu_device_id, gpu_device_stream)
        
    END SUBROUTINE prefetch_TimeInvariants_to_GPU

!-----------------------------------------------------------------------

END MODULE MOD_CoLMMAIN_CUDA
