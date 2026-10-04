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

module errors

implicit none

    integer,parameter::NO_ERROR = 0

    !>>>> ERROR
    integer,parameter::ERR_UNKNOWN_ERROR = 1

    !>>>> ERROR: argument list is empty (solver_appli.f90)
    integer,parameter::ERR_ARGUMENT_LIST_IS_EMPTY = 2

    !>>>> ERROR: data structure creation failed (solver_appli.f90)
    integer,parameter::ERR_DATA_STRUCTURE_CREATION_FAILED = 3

    !>>>> ERROR: video_sampling() failed ! (solver_appli.f90)
    integer,parameter::ERR_VIDEO_SAMPLING_FAILED = 4

    !>>>> ERROR: generating img_ref failed (solver_appli.f90)
    integer,parameter::ERR_GENERATING_IMG_REF_FAILED = 5

    !>>>> ERROR: images stabilisation failed (solver_appli.f90)
    integer,parameter::ERR_IMAGES_STABILISATION_FAILED = 6

    !>>>> ERROR: The folder '//trim(argmnt)//' does not exist (solver_appli.f90)
    integer,parameter::ERR_FOLDER_DOES_NOT_EXIST = 7

    !>>>> ERROR: something went wrong during the image extraction :
    !the number of images from ffmpeg is greater than the actual number of images (solver_appli.f90)
    integer,parameter::ERR_IMAGE_EXTRACTION = 8

    !>>>> ERROR : not enough points in GRP.dat file (solver_appli.f90, gen_img_ref.f90)
    integer,parameter::ERR_NOT_ENOUGH_POINTS_IN_GRP_FILE = 9

    !>>>> ERROR computing A coeff ; nbc not equal to 8 or 11 (solver_appli.f90, sub_verif_ortho_23D.f90, gen_img_ref.f90)
    integer,parameter::ERR_COMPUTING_COEF = 10

    !>>>> ERROR: this version works only with orthorectification 2D (solver_appli.f90)
    integer,parameter::ERR_ORTHORECTIFICATION_NOT_2D = 11

    !>>>> ERROR : sub_transf_img_2D() failed (solver_appli.f90)
    integer,parameter::ERR_SUB_TRANSF_IMG_2D_FAILED = 12

    !>>>> ERROR : sub_transf_img_3D() failed (solver_appli.f90)
    integer,parameter::ERR_SUB_TRANSF_IMG_3D_FAILED = 13

    !>>>> ERROR : sub_transf_img_0() failed (solver_appli.f90)
    integer,parameter::ERR_SUB_TRANSF_IMG_0_FAILED = 14

    !>>>> ERROR: image0001_transf.pgm is not a PGM P2 (solver_appli.f90)
    integer,parameter::ERR_IMAGE0001_NOT_PMG = 15

    !>>>> ERROR: flow direction not defined (solver_appli.f90)
    integer,parameter::ERR_FLOW_DIRECTION_NOT_DEFINED = 16

    !>>>> ERROR while reading a file (solver_appli.f90)
    integer,parameter::ERR_READING_FILE = 17

    !>>>> ERROR empty file (solver_appli.f90)
    integer,parameter::ERR_EMPTY_FILE = 18

    !>>>> ERROR while writing a file (solver_appli.f90)
    integer,parameter::ERR_WRITING_FILE = 19

    !>>>> ERROR user email is not a valid address (solver_appli.f90)
    integer,parameter::ERR_USER_EMAIL_ADRESS_NOT_VALID = 20

    !sub_vel_scal() : Erreur de lecture de list_avg.dat (sub_vel_scal.f90, sub_moy_scal.f90, sub_filter.f90)
    integer,parameter::ERR_READ_LIST_AVG = 21

    !sub_vel_scal() : Erreur de lecture de '//trim(NomIn) (sub_vel_scal.f90, sub_moy_scal.f90)
    integer,parameter::ERR_READ_FILTER = 22

    !sub_vel_scal() : Valeur de nb_data_points fausse (sub_vel_scal.f90, sub_moy_scal.f90)
    integer,parameter::ERR_NB_DATA_POINT_WRONG_VALUE = 23

    !>>>> ERROR : orthorectification solver failed (transf_23D.f90)
    integer,parameter::ERR_ORTHORECTIFICATION_SERVER_FAILED = 24

    !>>>> ERROR: ',GRP_dat,' file not found (compute_resolution.f90, gen_img_ref.f90)
    integer,parameter::ERR_GRP_FILE_NOT_FOUND = 25

    !>>>> ERREUR : il faut fournir 2 arguments (moy_ec.f90, Q_compute.f90)
    integer,parameter::ERR_NO_ARGUMENT_1 = 26

    !>>>> ERREUR : il faut fournir un 2e argument (moy_ec.f90, Q_compute.f90)
    integer,parameter::ERR_NO_ARGUMENT_2 = 27

    !Something went wrong with an external command (lib_util_solver.f90)
    integer,parameter::ERR_BAD_COMMAND = 28

    !error reading PIV param (lire_PIV_param.f90)
    integer,parameter::ERR_READ_PIV_PARAMETER = 29

    !>>>> ERROR in moy_ec.f90 : the number of records in the file ', trim(nomfich),' is not equal to the number of records in previous files (lire_PIV_param.f90)
    integer,parameter::ERR_SUB_MOY_EC = 30

    !>>>> ERROR reading GRP.dat header. This file seems to not being a GRP.dat V2.0 (gen_img_ref.f90)
    integer,parameter::ERR_GRP_FILE_WRONG_HEADER = 31

    !>>>> ERROR during purge subroutine
    integer,parameter::ERR_PURGE = 32

    !>>>> ERROR for StreamwiseVel filter : no transect data (bathy_p.dat)
    integer,parameter::ERR_STREAMWISE_FILTER_NO_TRANSECT = 33

end module errors
