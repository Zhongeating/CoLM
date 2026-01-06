# # GNU
# cd include
# ln -sf Makeoptions.gnu Makeoptions
# cd ..
# # make clean
# make -j160
# cd run
# mpirun -np 3 --mca coll_hcoll_enable 0 ./colm.x ./GreaterBay_Grid_Test.nml > Test_CPU.log 2>&1
# mpirun -np 3 --mca coll_hcoll_enable 0 ./colm.x ./GreaterBay_Grid_Test.nml > Test_CPU.log 2>&1
# cd ..

# CUDA
cd include
ln -sf Makeoptions.cuda Makeoptions
cd ..
# make clean
make -j160
cd run
mpirun -np 3 --mca coll_hcoll_enable 0 ./colm.x ./GreaterBay_Grid_Test.nml > Test_GPU.log 2>&1
cd ..