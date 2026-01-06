# CoLM CMake 构建系统使用说明

## 概述

本项目现在支持使用 CMake 进行构建，作为原有 Makefile 构建系统的替代方案。CMake 提供了更好的跨平台支持和更灵活的配置选项。

## 快速开始

### 基本构建步骤

```bash
# 1. 创建构建目录
mkdir build
cd build

# 2. 配置项目（使用默认选项）
cmake ..

# 3. 编译
make -j$(nproc)
```

### 指定编译器

```bash
# 使用 MPI Fortran 编译器
cmake -DCMAKE_Fortran_COMPILER=mpifort ..

# 使用 Intel Fortran 编译器
cmake -DCMAKE_Fortran_COMPILER=ifort ..

# 使用 GNU Fortran 编译器
cmake -DCMAKE_Fortran_COMPILER=gfortran ..
```

## 配置选项

### 空间结构类型 (SPATIAL_TYPE)

选择以下之一：
- `GRIDBASED` (默认) - 网格化
- `CATCHMENT` - 流域
- `UNSTRUCTURED` - 非结构化
- `SinglePoint` - 单点

```bash
cmake -DSPATIAL_TYPE=CATCHMENT ..
```

### 土地覆盖分类 (LULC_TYPE)

选择以下之一：
- `LULC_USGS` - USGS 分类
- `LULC_IGBP` (默认) - IGBP 分类
- `LULC_IGBP_PFT` - IGBP PFT 分类
- `LULC_IGBP_PC` - IGBP PC 分类

```bash
cmake -DLULC_TYPE=LULC_IGBP_PFT ..
```

### 土壤水力学模型 (SOIL_MODEL)

选择以下之一：
- `Campbell` (默认) - Campbell 模型
- `vanGenuchten_Mualem` - van Genuchten-Mualem 模型

```bash
cmake -DSOIL_MODEL=vanGenuchten_Mualem ..
```

### 可选功能开关

| 选项 | 描述 | 默认值 |
|------|------|--------|
| `ENABLE_MPI` | 启用 MPI 并行化 | ON |
| `ENABLE_URBAN_MODEL` | 启用 3D 城市模型 | OFF |
| `ENABLE_BGC` | 启用 BGC 生物地球化学模型 | OFF |
| `ENABLE_CROP` | 启用作物模型 | OFF |
| `ENABLE_LULCC` | 启用土地利用变化 | OFF |
| `ENABLE_DATA_ASSIMILATION` | 启用数据同化 | OFF |
| `ENABLE_CAMA_FLOOD` | 启用 CaMa-Flood 模型 | OFF |
| `ENABLE_CATCH_LATERAL_FLOW` | 启用流域侧向流 | OFF |
| `ENABLE_GRID_RIVER_LAKE_FLOW` | 启用网格河湖流 | OFF |

示例：
```bash
cmake -DENABLE_BGC=ON -DENABLE_URBAN_MODEL=ON ..
```

### 调试选项

| 选项 | 描述 | 默认值 |
|------|------|--------|
| `ENABLE_DEBUG` | 启用调试信息输出 | OFF |
| `ENABLE_RANGE_CHECK` | 启用变量范围检查 | OFF |
| `ENABLE_SRFDATA_DIAG` | 启用地表数据诊断 | OFF |

### NetCDF 配置

如果 CMake 无法自动找到 NetCDF，可以手动指定路径：

```bash
cmake -DNETCDF_LIB=/path/to/netcdf/lib -DNETCDF_INC=/path/to/netcdf/include ..
```

## 构建目标

| 目标 | 描述 |
|------|------|
| `mksrfdata.x` | 地表数据生成器 |
| `mkinidata.x` | 初始数据生成器 |
| `colm.x` | 主 CoLM 可执行文件 |
| `hist_concatenate.x` | 历史数据合并工具 |
| `srfdata_concatenate.x` | 地表数据合并工具 |
| `post_vector2grid.x` | 向量转网格工具（非 GRIDBASED 模式） |
| `colm` | 静态库 |
| `postprocess` | 所有后处理工具 |
| `all_executables` | 所有可执行文件 |

### 构建特定目标

```bash
# 只构建主程序
make colm.x

# 只构建地表数据生成器
make mksrfdata.x

# 构建所有后处理工具
make postprocess

# 构建静态库
make colm
```

## 构建类型

CMake 支持不同的构建类型：

```bash
# Debug 构建（包含调试信息）
cmake -DCMAKE_BUILD_TYPE=Debug ..

# Release 构建（优化）
cmake -DCMAKE_BUILD_TYPE=Release ..

# RelWithDebInfo 构建（优化 + 调试信息）
cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
```

## 完整配置示例

### 示例 1：基本网格化模式

```bash
mkdir build && cd build
cmake -DSPATIAL_TYPE=GRIDBASED \
      -DLULC_TYPE=LULC_IGBP \
      -DENABLE_MPI=ON \
      ..
make -j8
```

### 示例 2：启用 BGC 的 PFT 模式

```bash
mkdir build && cd build
cmake -DSPATIAL_TYPE=GRIDBASED \
      -DLULC_TYPE=LULC_IGBP_PFT \
      -DENABLE_BGC=ON \
      -DENABLE_MPI=ON \
      ..
make -j8
```

### 示例 3：流域模式带侧向流

```bash
mkdir build && cd build
cmake -DSPATIAL_TYPE=CATCHMENT \
      -DLULC_TYPE=LULC_IGBP \
      -DENABLE_CATCH_LATERAL_FLOW=ON \
      -DENABLE_MPI=ON \
      ..
make -j8
```

### 示例 4：带 CaMa-Flood 的完整配置

```bash
mkdir build && cd build
cmake -DSPATIAL_TYPE=GRIDBASED \
      -DLULC_TYPE=LULC_IGBP \
      -DENABLE_MPI=ON \
      -DENABLE_CAMA_FLOOD=ON \
      -DENABLE_URBAN_MODEL=ON \
      ..
make -j8
```

### 示例 5：单点模式

```bash
mkdir build && cd build
cmake -DSPATIAL_TYPE=SinglePoint \
      -DLULC_TYPE=LULC_IGBP \
      ..
make -j8
```

## 安装

```bash
# 安装到默认位置 (/usr/local)
sudo make install

# 安装到自定义位置
cmake -DCMAKE_INSTALL_PREFIX=/path/to/install ..
make install
```

## 清理构建

```bash
# 在构建目录中
make clean

# 完全清理（删除构建目录）
cd ..
rm -rf build
```

## 与原 Makefile 的对应关系

| Makefile 目标 | CMake 目标 |
|---------------|------------|
| `make all` | `make` 或 `make all` |
| `make mksrfdata.x` | `make mksrfdata.x` |
| `make mkinidata.x` | `make mkinidata.x` |
| `make colm.x` | `make colm.x` |
| `make postprocess.x` | `make postprocess` |
| `make lib` | `make colm` |
| `make clean` | `make clean` 或删除 build 目录 |

## 注意事项

1. **选项冲突处理**：CMake 会自动处理选项之间的冲突，例如：
   - SinglePoint 模式会自动禁用 MPI 和 CaMa-Flood
   - BGC 需要 LULC_IGBP_PFT 或 LULC_IGBP_PC
   - CaMa-Flood 需要 MPI

2. **可执行文件位置**：所有可执行文件会输出到 `run/` 目录

3. **模块文件**：Fortran 模块文件会输出到 `build/modules/` 目录

4. **静态库**：静态库会输出到 `lib/` 目录

## 故障排除

### 找不到 NetCDF

```bash
cmake -DNETCDF_LIB=/usr/local/lib -DNETCDF_INC=/usr/local/include ..
```

### 找不到 MPI

确保 MPI 已安装并在 PATH 中：
```bash
which mpifort
cmake -DCMAKE_Fortran_COMPILER=$(which mpifort) ..
```

### 编译错误

1. 检查编译器版本是否兼容
2. 确保所有依赖库已正确安装
3. 尝试使用 Debug 构建查看详细错误信息：
   ```bash
   cmake -DCMAKE_BUILD_TYPE=Debug ..
   make VERBOSE=1
