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
! Library for LSPIV-solvers, V2.0, 2019
!
! Jerome Le Coz & Jean-Baptiste Faure, Irstea
!
! Contributions:
! -------------
! LSPIV-solvers was built on original developments from the PhD work of
! Alex Hauet (LTHE Grenoble, University of Iowa), following the seminal works
! on LSPIV by Ichiro Fujita and Marian Muste.
! Recent contributions by Alex Hauet (EDF) and Magali Jodeau (EDF) are also acknowledged.

module global_solver_appli
! global variables for solver_appli program
   use lspiv_parameter, only: dp, point2D
   implicit none
   character (len=13), parameter :: final_results = 'final_results'
   character (len=20), parameter :: version_number = '0.34'
   character (len=14), parameter :: stab_param = 'stab_param.dat'
   character (len=16), parameter :: ffmpeg_dat = 'user_extract.dat' !extraction parameters for ffmpeg
   character (len=14), parameter :: mean_vel_0 = 'mean_vel_0.png' !raw output image
   character (len=14), parameter :: mean_vel_1 = 'mean_vel_1.png' !2nd raw output image
   character (len=12), parameter :: mean_vel = 'mean_vel.png' !output image
   character (len=17), parameter :: user_velocity = 'user_velocity.dat' !user defined : flow direction and velocity magnitude
   character (len=19), parameter :: user_transect = 'section_profile.dat' !user defined : transect for the discharge computation
   character (len=16), parameter :: logo_flowpic='FlowPic_logo.png'
   character (len=3),  parameter :: version_flowpic='0.5'

   character(len=19) :: simulation_date
   character(len=19) :: video_creation_time='0000-00-00T00:00:00'

   integer :: report_file  !logical unit for the report file
   integer :: nb_images    !number of images extracted from the video

   logical :: keepAllFiles

   !metadata from video
   real(kind=dp) :: fps, time_length, resolution

   character(len=250) :: pwd !directory from where the appli is run
   character(len=250) :: exedir !installation path, initialized by subroutine base_directory

   type(point2D) :: grid_step
   character (len=16) :: surface_coeff

end module global_solver_appli
