# CoLM 代码结构分析文档

## 1. 项目概述

**项目名称**: CoLM (Common Land Model)
**代码规模**:
- 总Fortran文件数: 344个
- main目录: 67个文件，约107,375行代码
- share目录: 22个文件，约22,423行代码
- cudamain目录: 1个文件，约789行
- cudamain_bak目录: 39个CUDA移植文件

---

## 2. define.h 启用的功能模块分析

根据 `include/define.h` 文件，当前配置启用的功能模块如下:

### 2.1 空间结构 (已启用)
- **GRIDBASED** - 基于网格的结构

### 2.2 土地分类 (已启用)
- **LULC_IGBP** - IGBP土地覆盖分类

### 2.3 MPI并行化 (已启用)
- **USEMPI** - 启用MPI并行

### 2.4 水文过程 (已启用)
- **Campbell_SOIL_MODEL** - Campbell土壤水力模型
- **CatchLateralFlow** - 侧向水流

### 2.5 未启用的功能
- ❌ CaMa_Flood (洪水模型)
- ❌ BGC (生物地球化学模型)
- ❌ CROP (作物模型)
- ❌ LULCC (土地覆盖变化)
- ❌ DataAssimilation (数据同化)
- ❌ URBAN_MODEL (3D城市模型)

---

## 3. 目录结构

```
CoLM202X_20260104/
├── config.f90          # 配置文件
├── config.mk           # Make配置
├── Makefile            # 主Makefile
├── include/
│   ├── define.h        # 功能开关定义
│   └── Makeoptions.*   # 编译器选项
├── main/               # 主程序模块 (67个文件, 107,375行)
├── share/              # 共享模块 (22个文件, 22,423行)
├── cudamain/           # CUDA主程序
├── cudamain_bak/       # CUDA移植备份 (39个文件)
├── run/                # 运行目录
├── mksrfdata/          # 地表数据生成
├── preprocess/         # 预处理
├── postprocess/        # 后处理
├── extends/            # 扩展模块 (CaMa等)
└── cuda_mod/           # CUDA模块文件 (.mod)
```

---

## 4. 主要程序入口 (Program)

| 文件 | 程序名 | 说明 |
|------|--------|------|
| `main/CoLM.F90` | `PROGRAM CoLM` | 主程序入口 |

---

## 5. 主要模块列表 (Module)

### 5.1 main目录模块 (按功能分类)

#### 核心控制模块
| 文件 | 模块名 | 功能描述 |
|------|--------|----------|
| `CoLMDRIVER.F90` | - | 驱动模块 |
| `CoLMMAIN.F90` | - | 主计算子程序 (1609行) |
| `MOD_CheckEquilibrium.F90` | MOD_CheckEquilibrium | 平衡检查 |
| `MOD_Hist.F90` | MOD_Hist | 历史输出 |
| `MOD_HistGridded.F90` | MOD_HistGridded | 网格历史输出 |
| `MOD_HistVector.F90` | MOD_HistVector | 向量历史输出 |
| `MOD_HistSingle.F90` | MOD_HistSingle | 单点历史输出 |
| `MOD_HistWriteBack.F90` | MOD_HistWriteBack | 历史数据回写 |

#### 常量定义模块
| 文件 | 模块名 | 功能描述 |
|------|--------|----------|
| `MOD_Const_LC.F90` | MOD_Const_LC | 土地覆盖常量 |
| `MOD_Const_PFT.F90` | MOD_Const_PFT | PFT常量 |
| `MOD_Const_Physical.F90` | MOD_Const_Physical | 物理常量 |

#### 变量模块 (Vars)
| 文件 | 模块名 |
|------|--------|
| `MOD_Vars_Global.F90` | MOD_Vars_Global |
| `MOD_Vars_TimeInvariants.F90` | MOD_Vars_TimeInvariants, MOD_Vars_PFTimeInvariants |
| `MOD_Vars_TimeVariables.F90` | MOD_Vars_TimeVariables, MOD_Vars_PFTimeVariables |
| `MOD_Vars_1DForcing.F90` | MOD_Vars_1DForcing |
| `MOD_Vars_2DForcing.F90` | MOD_Vars_2DForcing |
| `MOD_Vars_1DFluxes.F90` | MOD_Vars_1DFluxes |
| `MOD_Vars_1DAccFluxes.F90` | MOD_Vars_1DAccFluxes |
| `MOD_Vars_1DPFTFluxes.F90` | MOD_Vars_1DPFTFluxes |

#### 陆面过程模块
| 文件 | 模块名 | 功能描述 |
|------|--------|----------|
| `MOD_LeafTemperature.F90` | MOD_LeafTemperature | 叶片温度 |
| `MOD_LeafTemperaturePC.F90` | MOD_LeafTemperaturePC | 叶片温度(光合途径) |
| `MOD_LeafInterception.F90` | MOD_LeafInterception | 植被截留 |
| `MOD_GroundTemperature.F90` | MOD_GroundTemperature | 地表温度 |
| `MOD_GroundFluxes.F90` | MOD_GroundFluxes | 地表通量 |
| `MOD_FrictionVelocity.F90` | MOD_FrictionVelocity | 摩擦速度 |
| `MOD_TurbulenceLEddy.F90` | MOD_TurbulenceLEddy | 湍流涡流 |
| `MOD_Thermal.F90` | MOD_Thermal | 热力过程 |
| `MOD_NetSolar.F90` | MOD_NetSolar | 净太阳辐射 |
| `MOD_Albedo.F90` | MOD_Albedo | 地表反照率 |

#### 雪冰水过程模块
| 文件 | 模块名 | 功能描述 |
|------|--------|----------|
| `MOD_SnowFraction.F90` | MOD_SnowFraction | 雪盖比例 |
| `MOD_NewSnow.F90` | MOD_NewSnow | 新雪 |
| `MOD_SnowLayersCombineDivide.F90` | MOD_SnowLayersCombineDivide | 雪层合并/分割 |
| `MOD_SnowSnicar.F90` | MOD_SnowSnicar | SNICAR雪模型 |
| `MOD_PhaseChange.F90` | MOD_PhaseChange | 相变过程 |
| `MOD_RainSnowTemp.F90` | MOD_RainSnowTemp | 雨雪温度 |
| `MOD_Qsadv.F90` | MOD_Qsadv | 蒸发散adv |

#### 水文过程模块
| 文件 | 模块名 | 功能描述 |
|------|--------|----------|
| `MOD_Runoff.F90` | MOD_Runoff | 径流 |
| `MOD_PlantHydraulic.F90` | MOD_PlantHydraulic | 植物水力 |
| `MOD_SoilSnowHydrology.F90` | MOD_SoilSnowHydrology | 土壤-雪水文 |
| `MOD_SoilSurfaceResistance.F90` | MOD_SoilSurfaceResistance | 土壤表面阻力 |
| `MOD_SoilThermalParameters.F90` | MOD_SoilThermalParameters | 土壤热参数 |

#### 植被相关模块
| 文件 | 模块名 | 功能描述 |
|------|--------|----------|
| `MOD_3DCanopyRadiation.F90` | MOD_3DCanopyRadiation | 3D冠层辐射 |
| `MOD_CanopyLayerProfile.F90` | MOD_CanopyLayerProfile | 冠层剖面 |
| `MOD_Eroot.F90` | MOD_Eroot | 根系分布 |
| `MOD_LAIReadin.F90` | MOD_LAIReadin | LAI读取 |
| `MOD_LAIEmpirical.F90` | MOD_LAIEmpirical | LAI经验模型 |
| `MOD_AssimStomataConductance.F90` | MOD_AssimStomataConductance | 气孔导度 |

#### 湖泊与冰川模块
| 文件 | 模块名 | 功能描述 |
|------|--------|----------|
| `MOD_Lake.F90` | MOD_Lake | 湖泊模型 |
| `MOD_Glacier.F90` | MOD_Glacier | 冰川模型 |
| `MOD_SimpleOcean.F90` | MOD_SimpleOcean | 简单海洋 |

#### 大气与强迫模块
| 文件 | 模块名 | 功能描述 |
|------|--------|----------|
| `MOD_Forcing.F90` | MOD_Forcing | 强迫数据 |
| `MOD_ForcingDownscaling.F90` | MOD_ForcingDownscaling | 强迫降尺度 |
| `MOD_UserSpecifiedForcing.F90` | MOD_UserSpecifiedForcing | 用户指定强迫 |
| `MOD_Ozone.F90` | MOD_Ozone | 臭氧 |
| `MOD_Aerosol.F90` | MOD_Aerosol | 气溶胶 |

#### 其他模块
| 文件 | 模块名 | 功能描述 |
|------|--------|----------|
| `MOD_OrbCoszen.F90` | MOD_OrbCoszen | 太阳天顶角 |
| `MOD_OrbCosazi.F90` | MOD_OrbCosazi | 太阳方位角 |
| `MOD_WetBulb.F90` | MOD_WetBulb | 湿球温度 |
| `MOD_Irrigation.F90` | MOD_Irrigation | 灌溉 |
| `MOD_FireData.F90` | MOD_FireData | 火灾数据 |
| `MOD_NdepData.F90` | MOD_NdepData | 氮沉降数据 |
| `MOD_NitrifData.F90` | MOD_NitrifData | 硝化数据 |
| `MOD_LightningData.F90` | MOD_LightningData | 闪电数据 |
| `MOD_MonthlyinSituCO2MaunaLoa.F90` | MOD_MonthlyinSituCO2MaunaLoa | CO2数据 |
| `MOD_CropReadin.F90` | MOD_CropReadin | 作物数据读取 |
| `MOD_VicParaReadin.F90` | MOD_VicParaReadin | VIC参数读取 |

### 5.2 share目录模块

| 文件 | 模块名 | 功能描述 |
|------|--------|----------|
| `MOD_Precision.F90` | MOD_Precision | 精度定义 |
| `MOD_Namelist.F90` | MOD_Namelist | namelist读取 |
| `MOD_SPMD_Task.F90` | MOD_SPMD_Task | MPI任务管理 |
| `MOD_TimeManager.F90` | MOD_TimeManager | 时间管理 |
| `MOD_Block.F90` | MOD_Block | 块数据结构 |
| `MOD_Pixel.F90` | MOD_Pixel | 像素数据结构 |
| `MOD_Mesh.F90` | MOD_Mesh | 网格数据结构 |
| `MOD_Grid.F90` | MOD_Grid | 网格 |
| `MOD_Pixelset.F90` | MOD_Pixelset | 像素集 |
| `MOD_NetCDFBlock.F90` | MOD_NetCDFBlock | NetCDF块读写 |
| `MOD_NetCDFVector.F90` | MOD_NetCDFVector | NetCDF向量读写 |
| `MOD_NetCDFPoint.F90` | MOD_NetCDFPoint | NetCDF点读写 |
| `MOD_NetCDFSerial.F90` | MOD_NetCDFSerial | NetCDF串行读写 |
| `MOD_DataType.F90` | MOD_DataType | 数据类型 |
| `MOD_SpatialMapping.F90` | MOD_SpatialMapping | 空间映射 |
| `MOD_RangeCheck.F90` | MOD_RangeCheck | 范围检查 |
| `MOD_Utils.F90` | MOD_Utils | 工具函数 |
| `MOD_UserDefFun.F90` | MOD_UserDefFun | 用户自定义函数 |
| `MOD_WorkerPushData.F90` | MOD_WorkerPushData | 数据推送 |
| `MOD_5x5DataReadin.F90` | MOD_5x5DataReadin | 5x5数据读取 |
| `MOD_CatchmentDataReadin.F90` | MOD_CatchmentDataReadin | 流域数据读取 |
| `MOD_IncompleteGamma.F90` | MOD_IncompleteGamma | 不完全Gamma函数 |

---

## 6. 模块调用树

### 6.1 主程序调用流程

```
PROGRAM CoLM (main/CoLM.F90)
│
├── MPI初始化 (USEMPI)
│   └── spmd_init()
│
├── 读取namelist
│   └── read_namelist()
│
├── 模块初始化
│   ├── MOD_Namelist
│   ├── MOD_Vars_Global
│   ├── MOD_Const_LC / MOD_Const_PFT / MOD_Const_Physical
│   ├── MOD_Vars_TimeInvariants
│   ├── MOD_Vars_TimeVariables
│   ├── MOD_Vars_1DForcing / MOD_Vars_2DForcing
│   ├── MOD_Vars_1DFluxes / MOD_Vars_1DAccFluxes
│   ├── MOD_Forcing
│   ├── MOD_Hist
│   ├── MOD_CheckEquilibrium
│   ├── MOD_TimeManager
│   ├── MOD_Block / MOD_Pixel / MOD_Mesh
│   ├── MOD_LandElm / MOD_LandPatch
│   ├── MOD_Ozone
│   ├── MOD_SrfdataRestart
│   ├── MOD_LAIReadin
│   ├── MOD_SnowSnicar (SnowAge_init, SnowOptics_init)
│   └── MOD_Aerosol (AerosolDepInit, AerosolDepReadin)
│
├── 时间循环 (MOD_TimeManager)
│   │
│   └── 每个时间步调用 CoLMMAIN (main/CoLMMAIN.F90)
│       │
│       ├── NetSolar - 净太阳辐射
│       ├── RainSnowTemp - 雨雪判别
│       │
│       ├── 植被截获 (patchtype = 0)
│       │   └── LEAF_interception
│       │
│       ├── 新雪 (patchtype = 0)
│       │   └── newsnow
│       │
│       ├── 热力过程 (patchtype = 0,1)
│       │   └── THERMAL
│       │
│       ├── 水文过程 (patchtype = 0)
│       │   └── WATER
│       │
│       ├── 雪压实 (patchtype = 0)
│       │   └── snowcompaction
│       │
│       ├── 雪层合并/分割 (patchtype = 0)
│       │   ├── snowlayerscombine
│       │   └── snowlayersdivide
│       │
│       ├── 冰川模型 (patchtype = 3)
│       │   ├── GLACIER_TEMP
│       │   └── GLACIER_WATER
│       │
│       ├── 湖泊模型 (patchtype = 4)
│       │   ├── newsnow_lake
│       │   ├── laketem
│       │   └── snowwater_lake
│       │
│       ├── 海洋/海冰 (ocean/sea ice)
│       │   └── SOCEAN
│       │
│       ├── 太阳天顶角
│       │   └── orb_coszen
│       │
│       ├── 雪比例
│       │   └── snowfraction
│       │
│       └── 地表反照率
│           ├── albland
│           └── albocean
│
└── 历史输出
    └── MOD_Hist
```

### 6.2 CoLMMAIN 内部调用子程序详情

CoLMMAIN (1609行) 是核心计算子程序，包含以下主要调用:

```fortran
SUBROUTINE CoLMMAIN (...)
   USE MOD_Precision
   USE MOD_Vars_Global
   USE MOD_Const_Physical
   USE MOD_Vars_TimeVariables
   USE MOD_SoilSnowHydrology
   USE MOD_LeafTemperature
   USE MOD_LeafInterception
   USE MOD_GroundTemperature
   USE MOD_GroundFluxes
   USE MOD_FrictionVelocity
   USE MOD_TurbulenceLEddy
   USE MOD_Thermal
   USE MOD_Albedo
   USE MOD_NetSolar
   USE MOD_SnowFraction
   USE MOD_NewSnow
   USE MOD_SnowLayersCombineDivide
   USE MOD_PhaseChange
   USE MOD_Runoff
   USE MOD_Qsadv
   USE MOD_RainSnowTemp
   USE MOD_Glacier
   USE MOD_Lake
   USE MOD_SimpleOcean
   USE MOD_OrbCoszen
   USE MOD_SnowSnicar
   USE MOD_Aerosol
   USE MOD_Ozone
   USE MOD_PlantHydraulic
   USE MOD_LAIEmpirical
   USE MOD_CanopyLayerProfile
   USE MOD_3DCanopyRadiation
   USE MOD_Eroot
   USE MOD_AssimStomataConductance
   USE MOD_SoilSurfaceResistance
   USE MOD_SoilThermalParameters
   USE MOD_Irrigation
   USE MOD_WetBulb

   ! 内部调用:
   ! - netsolar
   ! - rain_snow_temp
   ! - leaf_interception
   ! - newsnow
   ! - thermal
   ! - water
   ! - snowcompaction
   ! - snowlayerscombine
   ! - snowlayersdivide
   ! - glacier_temp
   ! - glacier_water
   ! - newsnow_lake
   ! - laketem
   ! - snowwater_lake
   ! - socean
   ! - orb_coszen
   ! - snowfraction
   ! - albland
   ! - albocean
   ! 等...
END SUBROUTINE CoLMMAIN
```

---

## 7. 关键变量类型

### 7.1 时间变量
- `deltim` - 时间步长 (秒)
- `idate(3)` - 输入日期 (year, julian day, seconds)
- `edate(3)` - 结束日期
- `sdate(3)` - 起始日期

### 7.2 强迫变量
- `forc_t` - 气温
- `forc_q` - 比湿
- `forc_prc` - 降水(对流)
- `forc_prl` - 降水(大尺度)
- `forc_psrf` - 地表气压
- `forc_us`, `forc_vs` - 风速
- `forc_sols`, `forc_soll` - 太阳辐射

### 7.3 状态变量
- `t_soisno` - 土壤/雪温度
- `wliq_soisno` - 雪/土壤液态水
- `wice_soisno` - 雪/土壤冰
- `snowdp` - 雪深
- `scv` - 雪盖
- `t_grnd` - 地表温度

---

## 8. CUDA移植模块列表 (cudamain_bak)

当前已有CUDA移植备份的模块 (39个文件):

| 序号 | CUDA模块文件 | 对应CPU模块 |
|------|--------------|-------------|
| 1 | CoLMDRIVER_CUDA.F90 | CoLMDRIVER.F90 |
| 2 | MOD_Aerosol_CUDA.F90 | MOD_Aerosol.F90 |
| 3 | MOD_Albedo_CUDA.F90 | MOD_Albedo.F90 |
| 4 | MOD_AllocatableVars_CUDA.F90 | - |
| 5 | MOD_AssimStomataConductance_CUDA.F90 | MOD_AssimStomataConductance.F90 |
| 6 | MOD_CanopyLayerProfile_CUDA.F90 | MOD_CanopyLayerProfile.F90 |
| 7 | MOD_ConstVars_CUDA.F90 | - |
| 8 | MOD_Eroot_CUDA.F90 | MOD_Eroot.F90 |
| 9 | MOD_FrictionVelocity_CUDA.F90 | MOD_FrictionVelocity.F90 |
| 10 | MOD_GroundFluxes_CUDA.F90 | MOD_GroundFluxes.F90 |
| 11 | MOD_GroundTemperature_CUDA.F90 | MOD_GroundTemperature.F90 |
| 12 | MOD_Hydro_SoilFunction_CUDA.F90 | - |
| 13 | MOD_Hydro_VIC_CUDA.F90 | - |
| 14 | MOD_Hydro_VIC_Variables_CUDA.F90 | - |
| 15 | MOD_Init_CUDA.F90 | - |
| 16 | MOD_Lake_CUDA.F90 | MOD_Lake.F90 |
| 17 | MOD_LeafInterception_CUDA.F90 | MOD_LeafInterception.F90 |
| 18 | MOD_LeafTemperature_CUDA.F90 | MOD_LeafTemperature.F90 |
| 19 | MOD_NetSolar_CUDA.F90 | MOD_NetSolar.F90 |
| 20 | MOD_NewSnow_CUDA.F90 | MOD_NewSnow.F90 |
| 21 | MOD_OrbCoszen_CUDA.F90 | MOD_OrbCoszen.F90 |
| 22 | MOD_Ozone_CUDA.F90 | MOD_Ozone.F90 |
| 23 | MOD_PhaseChange_CUDA.F90 | MOD_PhaseChange.F90 |
| 24 | MOD_PlantHydraulic_CUDA.F90 | MOD_PlantHydraulic.F90 |
| 25 | MOD_Qsadv_CUDA.F90 | MOD_Qsadv.F90 |
| 26 | MOD_RainSnowTemp_CUDA.F90 | MOD_RainSnowTemp.F90 |
| 27 | MOD_Runoff_CUDA.F90 | MOD_Runoff.F90 |
| 28 | MOD_SnowFraction_CUDA.F90 | MOD_SnowFraction.F90 |
| 29 | MOD_SnowLayersCombineDivide_CUDA.F90 | MOD_SnowLayersCombineDivide.F90 |
| 30 | MOD_SnowSnicar_CUDA.F90 | MOD_SnowSnicar.F90 |
| 31 | MOD_SoilSnowHydrology_CUDA.F90 | MOD_SoilSnowHydrology.F90 |
| 32 | MOD_SoilSurfaceResistance_CUDA.F90 | MOD_SoilSurfaceResistance.F90 |
| 33 | MOD_SoilThermalParameters_CUDA.F90 | MOD_SoilThermalParameters.F90 |
| 34 | MOD_SPMD_Task_CUDA.F90 | MOD_SPMD_Task.F90 |
| 35 | MOD_Thermal_CUDA.F90 | MOD_Thermal.F90 |
| 36 | MOD_TurbulenceLEddy_CUDA.F90 | MOD_TurbulenceLEddy.F90 |
| 37 | MOD_Utils_CUDA.F90 | MOD_Utils.F90 |
| 38 | MOD_Utils_CUDA_bak.F90 | MOD_Utils.F90 (备份) |
| 39 | MOD_WetBulb_CUDA.F90 | MOD_WetBulb.F90 |

---

## 9. CUDA改写优先级建议

基于define.h当前配置和模块调用频率，建议按以下优先级进行CUDA改写:

### 高优先级 (核心计算模块)
1. **MOD_LeafTemperature.F90** - 叶片温度计算 (调用频繁)
2. **MOD_GroundFluxes.F90** - 地表通量 (核心物理)
3. **MOD_Thermal.F90** - 热力过程 (核心物理)
4. **MOD_SoilSnowHydrology.F90** - 土壤雪水文 (核心水文)
5. **MOD_NetSolar.F90** - 净太阳辐射 (辐射计算)

### 中优先级 (雪冰水过程)
6. **MOD_SnowSnicar.F90** - SNICAR雪模型
7. **MOD_PhaseChange.F90** - 相变过程
8. **MOD_SnowLayersCombineDivide.F90** - 雪层管理
9. **MOD_Runoff.F90** - 径流

### 一般优先级 (辅助模块)
10. **MOD_Albedo.F90** - 反照率
11. **MOD_FrictionVelocity.F90** - 摩擦速度
12. **MOD_LeafInterception.F90** - 植被截获
13. **MOD_TurbulenceLEddy.F90** - 湍流
14. **MOD_GroundTemperature.F90** - 地表温度
15. **MOD_NewSnow.F90** - 新雪

---

## 10. 编译与运行

### 编译配置
```bash
cd include
ln -sf Makeoptions.gnu Makeoptions  # CPU模式
# 或
ln -sf Makeoptions.cuda Makeoptions  # GPU模式

make clean
make -j160
```

### 运行
```bash
cd run
mpirun -np 3 --mca coll_hcoll_enable 0 ./colm.x ./GreaterBay_Grid_Test.nml
```

---

## 11. 文件统计汇总

| 目录 | 文件数 | 代码行数 | 主要内容 |
|------|--------|----------|----------|
| main/ | 67 | 107,375 | 主程序和物理模块 |
| share/ | 22 | 22,423 | 共享工具和数据I/O |
| cudamain/ | 1 | 789 | CUDA主程序 |
| cudamain_bak/ | 39 | - | CUDA移植备份 |
| extends/CaMa/ | ~100+ | - | CaMa-Flood扩展 |
| mksrfdata/ | 20+ | - | 地表数据生成 |
| postprocess/ | 5+ | - | 后处理工具 |
| **总计** | **344+** | **~130,000+** | |

---

*文档生成日期: 2026-02-15*
*CoLM版本: CoLM202X_20260104*
