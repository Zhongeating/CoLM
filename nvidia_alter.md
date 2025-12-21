# NVIDIA HPC SDK 编译 CoLM202X 记录

## 1. include/Makeoptions
    链接至include/Makeoptions.nvidia

## 2. Makefile
    -module .bld 之间添加空格

## 3. r16不可编译，全部转为r8
    main/MOD_3DCanopyRadiation.F90
    main/URBAN/MOD_Urban_Longwave.F90
    main/URBAN/MOD_Urban_Shortwave.F90

## 4. isnan缺失，更改为isnan_ud
    mksrfdata/Aggregation_TopographyFactors.F90