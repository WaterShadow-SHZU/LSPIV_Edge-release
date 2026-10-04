!! This file is part of Image_Velocimetry_Solver, a fortran solver for image velocimetry.
!!
!! Copyright (C) 2022 INRAE
!!
!! Image_Velocimetry_Solver is free software; you can redistribute it and/or
!! modify it under the terms of the GNU Lesser General Public
!! License as published by the Free Software Foundation; either
!! version 3 of the License, or (at your option) any later version.
!!
!! Alternatively, you can redistribute it and/or
!! modify it under the terms of the GNU General Public License as
!! published by the Free Software Foundation; either version 2 of
!! the License, or (at your option) any later version.
!!
!! Image_Velocimetry_Solver is distributed in the hope that it will be useful, but
!! WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
!! FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License
!! or the GNU General Public License for more details.
!!
!! You should have received a copy of the GNU Lesser General Public
!! License and a copy of the GNU General Public License along with
!! Image_Velocimetry_Solver If not, see <http://www.gnu.org/licenses/>.

! ---------------------------
! LSPIV-solvers, V1.0, 2014
!
! Jerome Le Coz & Jean-Baptiste Faure, Irstea
!
! Contributions:
! -------------
! LSPIV-solvers was built on original developments from the PhD work of
! Alex Hauet (LTHE Grenoble, University of Iowa), following the seminal works
! on LSPIV by Ichiro Fujita and Marian Muste.
! Recent contributions by Alex Hauet (EDF) and Magali Jodeau (EDF) are also acknowledged.

program verif_ortho

!     check 3D ortho-rectification parameters by computing the orthorectified space coordinates (Xt,Yt) of the GRPs from their image coordinates (i,j) and vertical space coordinate (Z)
!    modif du 1-06-2011 MJ pour prise en compte des orthorectification 2d ou 3d


!     The input file GRP.dat should be formated as:
!     - 3 lines of header:
!         - The title: "GRP"
!         - The number of GRPs used; for example: "7". At least 6 GRPs are required.
!         - The label of the columns: "X  Y  Z  i  j"
!     - The GRPs coordinates: Space coordinates and image coordinates

!      The input file coeff.dat is produced by solver "ortho" it should be formated as :
!     - nb of coefficients si nb=8 transfo 2d (8 coeff) si nb=11 transfo 3d (11 coeff)
!    - values of coefficients

!      The output file GRP_test_ortho.dat will be formated as:
!     - 3 lines of header:
!         - The title: "GRP"
!         - The number of GRPs used; for example: "7". At least 6 GRPs are required.
!         - The label of the columns: "X  Y  Z  i  j  Xt  Yt  Dev"
!     - The GRPs coordinates: Space coordinates and image coordinates

   use lspiv_parameter
   use mod_verif_ortho, only: sub_verif_ortho

   implicit none

   call sub_verif_ortho('./'//outputs_dir)

end program verif_ortho
