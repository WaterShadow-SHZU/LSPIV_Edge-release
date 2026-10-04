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
#  -----------------------------------------------------------------  #
#  ARM (aarch64 / armv7) 版本 -- 由 LSPIV_Edge 工程维护             #
#  相对上游 makefile 的三处改动，均以 [ARM] 标注：                    #
#    [ARM-1] 编译器探测补一个无版本号的 gfortran 兜底                 #
#    [ARM-2] 去掉 -march=x86-64 -mtune=generic，改用 $(ARCHFLAGS)     #
#    [ARM-3] libgfortran 运行库路径按架构自适应，且缺失不致命         #
#  用法：                                                            #
#    make station        # 给脚本/批处理用（目录当命令行参数）         #
#    make fudaa_linux    # 给 GUI 用（.x 后缀，无后缀参数约定）        #
#  -----------------------------------------------------------------  #
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
# [ARM-2] 架构标志：上游写死 -march=x86-64 -mtune=generic，
#         aarch64 / armv7 上的 gfortran 不认识 x86-64 会直接报错。
#         这里抽成一个变量，默认按宿主架构自动判断：
#           linux-aarch64 / linux-armv7  -> -mcpu=native（保守且有本地优化）
#           其他（含 x86 复用本 makefile 时）-> 上游原值
#         想编"可在任意同架构板子上跑"的通用二进制就覆盖它：
#           make station ARCHFLAGS="-mcpu=cortex-a76+crc+crypto"
#         或   make station ARCHFLAGS=""
#---------------------------------------------------------------------#
HOST_ARCH := $(shell uname -m)
ifneq (,$(filter aarch64 armv7l armv6l arm64,$(HOST_ARCH)))
	ARCHFLAGS ?= -mcpu=native
else
	ARCHFLAGS ?= -march=x86-64 -mtune=generic
endif

#---------------------------------------------------------------------#
# [ARM-1] 编译器探测：Debian/Ubuntu 的包就叫 gfortran（无版本号后缀）。
#         上游只找 gfortran-10/-9/-8，在树莓派 OS 上会全部落空，
#         结果是 FC 留空、make 爬到一半报一堆莫名错误。
#         这里在链尾补一层裸 gfortran 兜底。
#---------------------------------------------------------------------#
FC	= gfortran-10
ifeq (,$(shell which gfortran-10))
	FC	= gfortran-9
	ifeq (,$(shell which gfortran-9))
		FC	= gfortran-8
		ifeq (,$(shell which gfortran-8))
			FC	= gfortran
		endif
	endif
endif
# 允许命令行强制指定：make station FC=aarch64-linux-gnu-gfortran-13
FC ?= gfortran

$(info [ARM-makefile] host=$(HOST_ARCH)  FC=$(FC)  ARCHFLAGS=$(ARCHFLAGS))

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
		FFLAGS	= -cpp -g -O $(warnings) -Dopenmp -fopenmp -fimplicit-none $(ARCHFLAGS) -fcheck=all -fbacktrace -ffpe-trap=invalid,zero,overflow -finit-real=nan
		LFLAGS	= -no-pie
	else
		FFLAGS	= -cpp -g -O $(warnings) -fimplicit-none $(ARCHFLAGS) -fno-automatic -fcheck=all -fbacktrace -ffpe-trap=invalid,zero,overflow -finit-real=nan
		LFLAGS	= -static -no-pie
	endif
else
	ifeq ($(openmp),YES)
		FFLAGS	= -cpp -Dopenmp -fopenmp -O3 -fimplicit-none $(ARCHFLAGS) -ffpe-summary=invalid,zero,overflow
		LFLAGS	= -no-pie
	else
		FFLAGS	= -cpp -O3 -fimplicit-none $(ARCHFLAGS) -fno-automatic -ffpe-summary=invalid,zero,overflow
		LFLAGS	= -static -no-pie
	endif
endif
WFFLAGS	= $(FFLAGS)
WLFLAGS	= -static -no-pie

#---------------------------------------------------------------------#
# [ARM-3] libgfortran.so.5 这个"打包分发"用的拷贝步骤：
#         上游写死 /lib/x86_64-linux-gnu/，在 aarch64 上必然失败，
#         而且 make 的行首是 cp 不带 -，会把整个目标直接打断。
#         这里做三件事：
#           1) 路径按 $(HOST_ARCH) 自适应；
#           2) 用 `|| true` 保证找不到也不中断构建；
#           3) 提供 NOCOPY=1 一键跳过（板上装了 gfortran 就不需要拷）。
#         注意：只要板上装了 gfortran，这个拷贝步骤完全不需要。
#---------------------------------------------------------------------#
ifeq ($(HOST_ARCH),aarch64)
	GF_LIBDIR ?= /lib/aarch64-linux-gnu
else ifneq (,$(filter armv7l armv6l,$(HOST_ARCH)))
	GF_LIBDIR ?= /lib/arm-linux-gnueabihf
else
	GF_LIBDIR ?= /lib/x86_64-linux-gnu
endif

ifdef NOCOPY
	COPY_GF = @echo "[ARM-makefile] NOCOPY=1，跳过 libgfortran 拷贝"
else
	COPY_GF = -cp $(GF_LIBDIR)/libgfortran.so.5 $(1)/ 2>/dev/null || true
endif

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
	$(call COPY_GF,$(EXEDIR)_$(cible0))
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
	@mkdir -p $(EXEDIR)_$(cible1)
	$(call COPY_GF,$(EXEDIR)_$(cible1))
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
	$(call COPY_GF,$(EXEDIR)_$(cible2))
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

$(cible4):  makefile
	@echo
	@echo "###############################################################"
	@echo "## building executables for "$(cible4)" (MS-Windows 64 bits) ##"
	@echo "###############################################################"
	@mkdir -p $(EXEDIR)_$(cible4)
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

#---------------------------------------------------------------------#
# clean
#---------------------------------------------------------------------#
clean:
	-rm -f *.o
	-rm -f *.mod
	-rm -f $(EXEDIR)_$(cible1)/*
	-rm -f $(EXEDIR)_$(cible2)/*.x
	-rm -f $(EXEDIR)_$(cible3)/*.exe
	-rm -f $(EXEDIR)_$(cible4)/*.exe
	-rm -f $(LIBDIR)_$(cible2)/*.so
	-rm -f $(LIBDIR)_$(cible3)/*.dll
	-rm -f $(LIBDIR)_$(cible4)/*.dll

#---------------------------------------------------------------------#
# all
#---------------------------------------------------------------------#
all: clean $(cible1) clean $(cible2) clean $(cible3) clean $(cible4)
