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

program prog_gen_mask

    use iso_fortran_env, only: error_unit, output_unit
    use errors, only: ERR_ARGUMENT_LIST_IS_EMPTY, ERR_FOLDER_DOES_NOT_EXIST
    use lspiv_parameter, only: dp
    use mod_gen_mask, only: sub_gen_mask

    implicit none

    integer :: iarg
    logical :: bExist
    character (len=:), allocatable :: WorkingDir
    character(len=180) :: cmdline, argmnt

    call get_command(cmdline)

    iarg = 1 ; call get_command_argument(iarg,argmnt)
    if (len_trim(argmnt) == 0) then
        write(error_unit,*) '>>>> ERROR: argument list is empty'
        stop ERR_ARGUMENT_LIST_IS_EMPTY
    else
        inquire (file=trim(argmnt)//'/.',exist=bExist)
        if (bExist) then
            allocate(character(len=len_trim(argmnt)) :: WorkingDir)
            WorkingDir = trim(argmnt)
            write(output_unit,*) 'The folder '//WorkingDir//' exist : OK!'
         else
            write(error_unit,'(/,3a)') '>>>> ERROR: The folder '//trim(argmnt)//' does not exist. Bye.'
            stop ERR_FOLDER_DOES_NOT_EXIST
        end if
    end if
    call sub_gen_mask(WorkingDir)

    deallocate(WorkingDir)

end program prog_gen_mask
