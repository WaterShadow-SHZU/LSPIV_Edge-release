## This file is part of Image_Velocimetry_Solver, a fortran solver for image velocimetry.
##
## Copyright (C) 2022 INRAE
##
## Image_Velocimetry_Solver is free software; you can redistribute it and/or
## modify it under the terms of the GNU Lesser General Public
## License as published by the Free Software Foundation; either
## version 3 of the License, or (at your option) any later version.
##
## Alternatively, you can redistribute it and/or
## modify it under the terms of the GNU General Public License as
## published by the Free Software Foundation; either version 2 of
## the License, or (at your option) any later version.
##
## Image_Velocimetry_Solver is distributed in the hope that it will be useful, but WITHOUT ANY
## WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
## FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License or the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU Lesser General Public
## License and a copy of the GNU General Public License along with
## Image_Velocimetry_Solver If not, see <http://www.gnu.org/licenses/>.


#######################################################################
#                                                                     #
#                    Makefile pour les codes LSPIV                    #
#                                                                     #
#######################################################################

.SUFFIXES: .o .f90 .f .for

#---------------------------------------------------------------------#
# PROGRAM NAME
#---------------------------------------------------------------------#
PRG_PIV	       = PIV
PRG_filter     = filter
PRG_moy_ec     = moy_ec
PRG_Qcompute   = Q_compute
PRG_transf     = transf_a
PRG_ortho      = ortho_plan
PRG_verif      = verif_ortho
PRG_bathy      = bathy_compute
PRG_vel_scal   = vel_scal
PRG_vel_transf = vel_transf
PRG_moy_scal   = moy_scal
PRG_img_ref    = gen_img_ref
PRG_appli      = solver_appli
PRG_gen_mask   = gen_mask
PRG_manual_vel = manual_vel

# source names
SRC_lib	       = global_solver_appli
SRC_PIV	       = PIV
SRC_filter     = filter
SRC_moy_ec     = moy_ec
SRC_Qcompute   = Q_compute
SRC_transf     = transf_23D
SRC_ortho      = ortho_plan_23D
SRC_verif      = verif_ortho_23D
SRC_bathy      = bathy_compute
SRC_vel_scal   = vel_scal
SRC_vel_transf = vel_transf
SRC_moy_scal   = moy_scal
SRC_img_ref    = gen_img_ref
SRC_appli      = solver_appli
SRC_gen_mask   = gen_mask
SRC_manual_vel = manual_vel
SRC_errors     = errors
SRC_kdtree     = kdtree2
SRC_utils      = errors.f90 sub_lspiv_parameter.f90

#---------------------------------------------------------------------#
# Directories
#---------------------------------------------------------------------#
machine := $(shell uname -n)
WORKDIR  =$(pwd)
EXEDIR   =./../exe
LIBDIR   =./../lib


#cibles
cible0=appli
cible1=station
cible2=fudaa_linux
cible3=fudaa_w7_32
cible4=fudaa_w7_64

#---------------------------------------------------------------------#
# Source and Objects files
#---------------------------------------------------------------------#
FC	= gfortran-10
ifeq (,$(shell which gfortran-10))  #cibles Linux
	FC	= gfortran-9
	ifeq (,$(shell which gfortran-9))
		FC	= gfortran-8
	endif
endif
# #cibles W7
WFC32	= i686-w64-mingw32-gfortran
WFC64	= x86_64-w64-mingw32-gfortran

#---------------------------------------------------------------------#
# compiler and Flags
#---------------------------------------------------------------------#
openmp = YES
debug = NO
warnings	= -Wpedantic -Wunused-variable -Waliasing -Wampersand -Wconversion -Wsurprising -Wintrinsics-std -Wno-tabs -Wintrinsic-shadow -Wline-truncation -Wreal-q-constant -Wuninitialized -Wextra -Wintrinsics-std -Wuse-without-only

ifeq ($(debug),YES)
	ifeq ($(openmp),YES)
		FFLAGS	= -cpp -g -O $(warnings) -Dopenmp -fopenmp -fimplicit-none -march=x86-64 -mtune=generic -fcheck=all -fbacktrace -ffpe-trap=invalid,zero,overflow -finit-real=nan
		LFLAGS	= -no-pie
	else
		FFLAGS	= -cpp -g -O $(warnings) -fimplicit-none -march=x86-64 -mtune=generic -fno-automatic -fcheck=all -fbacktrace -ffpe-trap=invalid,zero,overflow -finit-real=nan
		LFLAGS	= -static -no-pie
	endif
else
	ifeq ($(openmp),YES)
		FFLAGS	= -cpp -Dopenmp -fopenmp -O3 -fimplicit-none -march=x86-64 -mtune=generic -ffpe-summary=invalid,zero,overflow
		LFLAGS	= -no-pie
	else
		FFLAGS	= -cpp -O3 -fimplicit-none -mtune=generic -fno-automatic -ffpe-summary=invalid,zero,overflow
		LFLAGS	= -static -no-pie
	endif
endif
WFFLAGS	= $(FFLAGS)
WLFLAGS	= -static -no-pie
#-----------------------------------------------------------------------------------------------------#
# compile and link
#
# the directive openmp2 allows to choose between sequential and parallel version
# the conditional compilation option -Dopenmp2 should only be used for solver_appli (FlowPic solver)
#-----------------------------------------------------------------------------------------------------#
$(cible0):	makefile
	@echo
	@echo "########################################################"
	@echo "## building executable for "$(cible0)" (solver Appli) ##"
	@echo "########################################################"
	-rm *.mod
	cp /lib/x86_64-linux-gnu/libgfortran.so.5 $(EXEDIR)_$(cible0)/
	cp ./stab_img/src/exesurf $(EXEDIR)_$(cible0)/stab_image
	$(FC) $(FFLAGS) -Dopenmp2 -no-pie $(SRC_utils) $(SRC_kdtree).f90 -o $(EXEDIR)_$(cible0)/$(PRG_appli) $(SRC_lib).f90 \
	sub_$(SRC_PIV).f90 \
	sub_$(SRC_filter).f90 \
	sub_$(SRC_moy_ec).f90 \
	sub_$(SRC_Qcompute).f90 \
	sub_$(SRC_transf).f90 \
	sub_$(SRC_ortho).f90 \
	sub_$(SRC_verif).f90 \
	sub_$(SRC_bathy).f90 \
	sub_$(SRC_gen_mask).f90 \
	$(SRC_appli).f90

$(cible1):  makefile
	@echo
	@echo "####################################################"
	@echo "## building executables for "$(cible1)" (station) ##"
	@echo "####################################################"
# 	cp /lib/x86_64-linux-gnu/libgfortran.so.5 $(EXEDIR)_$(cible1)/
# 	cp ./stab_img/src/exesurf $(EXEDIR)_$(cible1)/stab_img
	$(FC) -Dversion_$(cible1) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible1)/$(PRG_PIV) $(LFLAGS) sub_$(SRC_PIV).f90 $(SRC_PIV).f90
	$(FC) -Dversion_$(cible1) $(FFLAGS) $(SRC_utils) $(SRC_kdtree).f90 -o $(EXEDIR)_$(cible1)/$(PRG_filter) $(LFLAGS) sub_$(SRC_filter).f90 $(SRC_filter).f90
	$(FC) -Dversion_$(cible1) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible1)/$(PRG_moy_ec) $(LFLAGS) sub_$(SRC_moy_ec).f90 $(SRC_moy_ec).f90
	$(FC) -Dversion_$(cible1) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible1)/$(PRG_Qcompute) $(LFLAGS) sub_$(SRC_Qcompute).f90 $(SRC_Qcompute).f90
	$(FC) -Dversion_$(cible1) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible1)/$(PRG_transf) $(LFLAGS) sub_$(SRC_transf).f90 $(SRC_transf).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible1)/$(PRG_ortho) $(LFLAGS) sub_$(SRC_ortho).f90 $(SRC_ortho).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible1)/$(PRG_verif) $(LFLAGS) sub_$(SRC_verif).f90 $(SRC_verif).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible1)/$(PRG_img_ref) $(LFLAGS) sub_$(SRC_ortho).f90 $(SRC_img_ref).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible1)/$(PRG_gen_mask) $(LFLAGS) sub_$(SRC_gen_mask).f90 $(SRC_gen_mask).f90
	@echo "#########################################"
	@echo "## creation of executables succeeded ! ##"
	@echo "#########################################"
	@echo

$(cible2):  makefile
	@echo
	@echo "##########################################################"
	@echo "## building executables for "$(cible2)" (Linux 64 bits) ##"
	@echo "##########################################################"
	@mkdir -p $(EXEDIR)_$(cible2)
	cp /lib/x86_64-linux-gnu/libgfortran.so.5 $(EXEDIR)_$(cible2)/
	cp ./stab_img/src/exesurf $(EXEDIR)_$(cible2)/stab_img.x
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_PIV).x $(LFLAGS) sub_$(SRC_PIV).f90 $(SRC_PIV).f90
	$(FC) $(FFLAGS) $(SRC_utils) $(SRC_kdtree).f90 -o $(EXEDIR)_$(cible2)/$(PRG_filter).x $(LFLAGS) sub_$(SRC_filter).f90 $(SRC_filter).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_moy_ec).x $(LFLAGS) sub_$(SRC_moy_ec).f90 $(SRC_moy_ec).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_Qcompute).x $(LFLAGS) sub_$(SRC_Qcompute).f90 $(SRC_Qcompute).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_transf).x $(LFLAGS) sub_$(SRC_transf).f90 $(SRC_transf).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_ortho).x $(LFLAGS) sub_$(SRC_ortho).f90 $(SRC_ortho).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_verif).x $(LFLAGS) sub_$(SRC_verif).f90 $(SRC_verif).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_bathy).x $(LFLAGS) sub_$(SRC_bathy).f90 $(SRC_bathy).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_vel_scal).x $(LFLAGS) sub_$(SRC_vel_scal).f90 $(SRC_vel_scal).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_moy_scal).x $(LFLAGS) sub_$(SRC_moy_scal).f90 $(SRC_moy_scal).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_vel_transf).x $(LFLAGS) sub_$(SRC_vel_transf).f90 $(SRC_vel_transf).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_img_ref).x $(LFLAGS) sub_$(SRC_ortho).f90 $(SRC_img_ref).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_gen_mask).x $(LFLAGS) sub_$(SRC_gen_mask).f90 $(SRC_gen_mask).f90
	$(FC) $(FFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible2)/$(PRG_manual_vel).x $(LFLAGS) $(SRC_manual_vel).f90
	@echo "#########################################"
	@echo "## creation of executables succeeded ! ##"
	@echo "#########################################"
	@echo
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_PIV).so sub_$(SRC_PIV).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) $(SRC_kdtree).f90 -o $(LIBDIR)_$(cible2)/$(PRG_filter).so $(LFLAGS) sub_$(SRC_filter).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_moy_ec).so $(LFLAGS) sub_$(SRC_moy_ec).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_Qcompute).so $(LFLAGS) sub_$(SRC_Qcompute).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_transf).so $(LFLAGS) sub_$(SRC_transf).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_ortho).so $(LFLAGS) sub_$(SRC_ortho).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_verif).so $(LFLAGS) sub_$(SRC_verif).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_bathy).so $(LFLAGS) sub_$(SRC_bathy).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_vel_scal).so $(LFLAGS) sub_$(SRC_vel_scal).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_moy_scal).so $(LFLAGS) sub_$(SRC_moy_scal).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_vel_transf).so $(LFLAGS) sub_$(SRC_vel_transf).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_gen_mask).so $(LFLAGS) sub_$(SRC_gen_mask).f90 -shared
	$(FC) $(FFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible2)/$(PRG_manual_vel).so $(LFLAGS) $(SRC_manual_vel).f90 -shared
	@echo "########################################"
	@echo "## creation of shared lib succeeded ! ##"
	@echo "########################################"
	@echo

$(cible3):  makefile
	@echo
	@echo "###############################################################"
	@echo "## building executables for "$(cible3)" (MS-Windows 32 bits) ##"
	@echo "###############################################################"
# 	@rm $(HOME)/.wine/drive_c/gcc
# 	@ln -s $(HOME)/.wine/drive_c/gcc32 $(HOME)/.wine/drive_c/gcc
	cp ./stab_img/src/exesurf.exe $(EXEDIR)_$(cible3)/stab_img.exe
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_PIV).exe $(WLFLAGS) sub_$(SRC_PIV).f90 $(SRC_PIV).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) $(SRC_kdtree).f90 -o $(EXEDIR)_$(cible3)/$(PRG_filter).exe $(WLFLAGS) sub_$(SRC_filter).f90 $(SRC_filter).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_moy_ec).exe $(WLFLAGS) sub_$(SRC_moy_ec).f90 $(SRC_moy_ec).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_Qcompute).exe $(WLFLAGS) sub_$(SRC_Qcompute).f90 $(SRC_Qcompute).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_transf).exe $(WLFLAGS) sub_$(SRC_transf).f90 $(SRC_transf).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_ortho).exe $(WLFLAGS) sub_$(SRC_ortho).f90 $(SRC_ortho).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_verif).exe $(WLFLAGS) sub_$(SRC_verif).f90 $(SRC_verif).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_bathy).exe $(WLFLAGS) sub_$(SRC_bathy).f90 $(SRC_bathy).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_vel_scal).exe $(WLFLAGS) sub_$(SRC_vel_scal).f90 $(SRC_vel_scal).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_moy_scal).exe $(WLFLAGS) sub_$(SRC_moy_scal).f90 $(SRC_moy_scal).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_vel_transf).exe $(WLFLAGS) sub_$(SRC_vel_transf).f90 $(SRC_vel_transf).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_img_ref).exe $(WLFLAGS) sub_$(SRC_ortho).f90 $(SRC_img_ref).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_gen_mask).exe $(WLFLAGS) sub_$(SRC_gen_mask).f90 $(SRC_gen_mask).f90
	$(WFC32) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible3)/$(PRG_manual_vel).exe $(WLFLAGS) $(SRC_manual_vel).f90
	@echo "#########################################"
	@echo "## creation of executables succeeded ! ##"
	@echo "#########################################"
	@echo
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_PIV).dll sub_$(SRC_PIV).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) $(SRC_kdtree).f90 -o $(LIBDIR)_$(cible3)/$(PRG_filter).dll $(LFLAGS) sub_$(SRC_filter).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_moy_ec).dll $(LFLAGS) sub_$(SRC_moy_ec).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_Qcompute).dll $(LFLAGS) sub_$(SRC_Qcompute).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_transf).dll $(LFLAGS) sub_$(SRC_transf).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_ortho).dll $(LFLAGS) sub_$(SRC_ortho).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_verif).dll $(LFLAGS) sub_$(SRC_verif).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_bathy).dll $(LFLAGS) sub_$(SRC_bathy).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_vel_scal).dll $(LFLAGS) sub_$(SRC_vel_scal).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_moy_scal).dll $(LFLAGS) sub_$(SRC_moy_scal).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_vel_transf).dll $(LFLAGS) sub_$(SRC_vel_transf).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_gen_mask).dll $(LFLAGS) sub_$(SRC_gen_mask).f90 -shared
	$(WFC32) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible3)/$(PRG_manual_vel).dll $(LFLAGS) $(SRC_manual_vel).f90 -shared
	@echo "########################################"
	@echo "## creation of shared lib succeeded ! ##"
	@echo "########################################"
	@echo

$(cible4):  makefile
	@echo
	@echo "###############################################################"
	@echo "## building executables for "$(cible4)" (MS-Windows 64 bits) ##"
	@echo "###############################################################"
	@mkdir -p $(EXEDIR)_$(cible4)
# 	@rm $(HOME)/.wine/drive_c/gcc
# 	@ln -s $(HOME)/.wine/drive_c/gcc64 $(HOME)/.wine/drive_c/gcc
	cp ./stab_img/src/exesurf.exe $(EXEDIR)_$(cible4)/stab_img.exe
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_PIV).exe $(WLFLAGS) sub_$(SRC_PIV).f90 $(SRC_PIV).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) $(SRC_kdtree).f90 -o $(EXEDIR)_$(cible4)/$(PRG_filter).exe $(WLFLAGS) sub_$(SRC_filter).f90 $(SRC_filter).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_moy_ec).exe $(WLFLAGS) sub_$(SRC_moy_ec).f90 $(SRC_moy_ec).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_Qcompute).exe $(WLFLAGS) sub_$(SRC_Qcompute).f90 $(SRC_Qcompute).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_transf).exe $(WLFLAGS) sub_$(SRC_transf).f90 $(SRC_transf).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_ortho).exe $(WLFLAGS) sub_$(SRC_ortho).f90 $(SRC_ortho).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_verif).exe $(WLFLAGS) sub_$(SRC_verif).f90  $(SRC_verif).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_bathy).exe $(WLFLAGS) sub_$(SRC_bathy).f90 $(SRC_bathy).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_vel_scal).exe $(WLFLAGS) sub_$(SRC_vel_scal).f90 $(SRC_vel_scal).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_moy_scal).exe $(WLFLAGS) sub_$(SRC_moy_scal).f90 $(SRC_moy_scal).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_vel_transf).exe $(WLFLAGS) sub_$(SRC_vel_transf).f90 $(SRC_vel_transf).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_img_ref).exe $(WLFLAGS) sub_$(SRC_ortho).f90 $(SRC_img_ref).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_gen_mask).exe $(WLFLAGS) sub_$(SRC_gen_mask).f90 $(SRC_gen_mask).f90
	$(WFC64) $(WFFLAGS) $(SRC_utils) -o $(EXEDIR)_$(cible4)/$(PRG_manual_vel).exe $(WLFLAGS) $(SRC_manual_vel).f90
	@echo "#########################################"
	@echo "## creation of executables succeeded ! ##"
	@echo "#########################################"
	@echo
	@echo
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_PIV).dll sub_$(SRC_PIV).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) $(SRC_kdtree).f90 -o $(LIBDIR)_$(cible4)/$(PRG_filter).dll $(LFLAGS) sub_$(SRC_filter).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_moy_ec).dll $(LFLAGS) sub_$(SRC_moy_ec).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_Qcompute).dll $(LFLAGS) sub_$(SRC_Qcompute).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_transf).dll $(LFLAGS) sub_$(SRC_transf).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_ortho).dll $(LFLAGS) sub_$(SRC_ortho).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_verif).dll $(LFLAGS) sub_$(SRC_verif).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_bathy).dll $(LFLAGS) sub_$(SRC_bathy).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_vel_scal).dll $(LFLAGS) sub_$(SRC_vel_scal).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_moy_scal).dll $(LFLAGS) sub_$(SRC_moy_scal).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_vel_transf).dll $(LFLAGS) sub_$(SRC_vel_transf).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_gen_mask).dll $(LFLAGS) sub_$(SRC_gen_mask).f90 -shared
	$(WFC64) $(WFFLAGS) -fPIC -no-pie $(SRC_utils) -o $(LIBDIR)_$(cible4)/$(PRG_manual_vel).dll $(LFLAGS) $(SRC_manual_vel).f90 -shared
	@echo "########################################"
	@echo "## creation of shared lib succeeded ! ##"
	@echo "########################################"
	@echo

#---------------------------------------------------------------------#
# clean
#---------------------------------------------------------------------#
clean:
	-rm *.o
	-rm *.mod
	-rm $(EXEDIR)_$(cible1)/*
	-rm $(EXEDIR)_$(cible2)/*.x
	-rm $(EXEDIR)_$(cible3)/*.exe
	-rm $(EXEDIR)_$(cible4)/*.exe
	-rm $(LIBDIR)_$(cible2)/*.so
	-rm $(LIBDIR)_$(cible3)/*.dll
	-rm $(LIBDIR)_$(cible4)/*.dll

#---------------------------------------------------------------------#
# all
#---------------------------------------------------------------------#
all: clean $(cible1) clean $(cible2) clean $(cible3) clean $(cible4)
