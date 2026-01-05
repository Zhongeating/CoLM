#include "include/define.h"
#ifdef GRIDBASED
SPATIAL_TYPE := gridbased
#endif
#ifdef CATCHMENT
SPATIAL_TYPE := catchment
#endif
#ifdef UNSTRUCTURED
SPATIAL_TYPE := unstructured
#endif
#ifdef SinglePoint
SPATIAL_TYPE := singlepoint
#endif

#ifdef BGC
BGC_ENABLED := YES
#else
BGC_ENABLED := NO
#endif

#ifdef URBAN_MODEL
URBAN_ENABLED := YES
#else
URBAN_ENABLED := NO
#endif

#ifdef LULCC
LULCC_ENABLED := YES
#else
LULCC_ENABLED := NO
#endif

#ifdef DataAssimilation
DA_ENABLED := YES
#else
DA_ENABLED := NO
#endif

#ifdef USEMPI
USEMPI_ENABLED := YES
#else
USEMPI_ENABLED := NO
#endif

#ifdef CaMa_Flood
CAMA_ENABLED := YES
#else
CAMA_ENABLED := NO
#endif

#ifdef CatchLateralFlow
CATCH_LATERAL := YES
#else
CATCH_LATERAL := NO
#endif

#ifdef GridRiverLakeFlow
GRID_RIVER := YES
#else
GRID_RIVER := NO
#endif

#ifdef LULC_IGBP_PFT
LULC_IGBP_PFT1 := YES
#else
LULC_IGBP_PFT1 := NO
#endif

#ifdef LULC_IGBP_PC
LULC_IGBP_PC1 := YES
#else
LULC_IGBP_PC1 := NO
#endif