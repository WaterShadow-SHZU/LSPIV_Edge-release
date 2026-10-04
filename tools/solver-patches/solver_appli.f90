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

! solveur pour l'appli LSPIV
module pipes_module

  use,intrinsic :: iso_c_binding

  implicit none

  public

  interface

    function popen(command, mode) bind(C,name='popen')
      import :: c_char, c_ptr
      character(kind=c_char),dimension(*) :: command
      character(kind=c_char),dimension(*) :: mode
      type(c_ptr) :: popen
    end function popen

    function fgets(s, siz, stream) bind(C,name='fgets_unlocked')
      import :: c_char, c_ptr, c_int
      type (c_ptr) :: fgets
      character(kind=c_char),dimension(*) :: s
      integer(kind=c_int),value :: siz
      type(c_ptr),value :: stream
    end function fgets

    function pclose(stream) bind(C,name='pclose')
      import :: c_ptr, c_int
      integer(c_int) :: pclose
      type(c_ptr),value :: stream
    end function pclose

  end interface

  public :: c2f_string, get_command_as_string

  interface get_command_as_string
    module procedure get_command_as_string1, get_command_as_string2, get_command_as_string3
  end interface

contains

!**********************************************
! convert a C string to a Fortran string
!**********************************************
  function c2f_string(c) result(f)

  implicit none

  character(len=*),intent(in)  :: c
  character(len=:),allocatable :: f

  integer :: i, j

  i = index(c,c_null_char)
  j = index(c(:i),c_new_line,.true.)

  if (i<=0) then
    f = c
  elseif (i==1) then
    f = ''
  elseif (i>1) then
    if (j==i-1) then
      f = c(1:i-2)
    else
      f = c(1:i-1)
    end if
  end if

  end function c2f_string

  elemental subroutine str2int(str,int,stat)
    implicit none
    character(len=*),intent(in) :: str
    integer,intent(out)         :: int
    integer,intent(out)         :: stat

    read(str,*,iostat=stat)  int
  end subroutine str2int

!**********************************************
! return the result of the command as a string
!**********************************************
  subroutine get_command_as_string1(command, str)

  implicit none

  character(len=*),intent(in)  :: command
  character(len=:),allocatable, intent(out) :: str

  integer,parameter :: buffer_length = 1000

  type(c_ptr) :: h
  integer(c_int) :: istat
  character(kind=c_char,len=buffer_length) :: line

  str = ''
  h = c_null_ptr
  h = popen(command//c_null_char,'r'//c_null_char)
  if (c_associated(h)) then
    do while (c_associated(fgets(line,buffer_length,h)))
      str = str//c2f_string(line)//c_new_line
    end do
    istat = pclose(h)
  end if

  end subroutine get_command_as_string1

!***********************************************************************
! return the result of the command as a string and the pid as an integer
!***********************************************************************
  subroutine get_command_as_string2(command, str, pid)

  implicit none

  character(len=*), intent(in)  :: command
  integer, intent(out) :: pid
  character(len=:),allocatable, intent(out) :: str

  integer,parameter :: buffer_length = 1000

  type(c_ptr) :: h
  integer(c_int) :: istat
  character(kind=c_char,len=buffer_length) :: line

  str = ''
  h = c_null_ptr
  h = popen(command//' & echo $!'//c_null_char,'r'//c_null_char)
  if (c_associated(h)) then
    if (c_associated(fgets(line,buffer_length,h))) call str2int(c2f_string(line),pid,istat)
    do while (c_associated(fgets(line,buffer_length,h)))
      str = str//c2f_string(line)//c_new_line
    end do
    istat = pclose(h)
  end if

  end subroutine get_command_as_string2

!*********************************************************************
! return the result of the command as a string and the pid as a string
!*********************************************************************
  subroutine get_command_as_string3(command, str, pid)

  implicit none

  character(len=*), intent(in)  :: command
  character(len=:),allocatable, intent(out) :: pid
  character(len=:),allocatable, intent(out) :: str

  integer,parameter :: buffer_length = 1000

  type(c_ptr) :: h
  integer(c_int) :: istat
  character(kind=c_char,len=buffer_length) :: line

  str = ''
  h = c_null_ptr
  h = popen(command//' & echo $!'//c_null_char,'r'//c_null_char)
  if (c_associated(h)) then
    if (c_associated(fgets(line,buffer_length,h))) pid = c2f_string(line)
    do while (c_associated(fgets(line,buffer_length,h)))
      str = str//c2f_string(line)//c_new_line
    end do
    istat = pclose(h)
  end if

  end subroutine get_command_as_string3

end module pipes_module



program solver_appli
! main program
   use iso_fortran_env, only: error_unit, output_unit
   use errors, only: ERR_ARGUMENT_LIST_IS_EMPTY, ERR_DATA_STRUCTURE_CREATION_FAILED, &
                     ERR_VIDEO_SAMPLING_FAILED, ERR_GENERATING_IMG_REF_FAILED, &
                     ERR_IMAGES_STABILISATION_FAILED, ERR_UNKNOWN_ERROR, ERR_FOLDER_DOES_NOT_EXIST
   use global_solver_appli, only: keepAllFiles, pwd, report_file, simulation_date, &
                                  version_number, user_transect, exedir
   use lspiv_parameter, only:  dp, h_dat, outputs_dir, vel_filter, &
                               discharge, duration
   use mod_transf_23D, only: read_PGM_P2, read_PGM_P2_solver
   use mod_filter, only: sub_filter
   use mod_moy_ec, only: sub_moy_ec
#ifdef openmp
   use omp_lib, only: omp_get_max_threads
#endif /* openmp */
   interface
      subroutine check_user_email(workdir,user_email)
      !check if there is a problem with user_email.dat
         character(len=*), intent(in) :: workdir
         character(len=:), allocatable, intent(out) :: user_email
      end subroutine check_user_email
      function Q_compute(workdir) result(Q)
         use lspiv_parameter, only: dp
         character(len=*), intent(in) :: workdir
         real(kind=dp) :: Q
      end function Q_compute
      subroutine gen_image_result(workdir, Q_user)
         use lspiv_parameter, only: dp
         implicit none
         ! -- prototype --
         character (len=*), intent(in) :: workdir !working directory
         real(kind=dp), intent(in), optional :: Q_user
      end subroutine gen_image_result
      subroutine finalize_results(workdir,user_email,istop,Q_user)
         use lspiv_parameter, only: dp
         implicit none
         ! -- prototype --
         character (len=*), intent(in) :: workdir !working directory
         character (len=*), intent(in) :: user_email !email where to send the results file
         integer,intent(out) :: istop
         real(kind=dp), intent(in), optional :: Q_user
      end subroutine finalize_results
   end interface

   ! -- local variables --
   integer :: iarg, values(8), vtime0(8), vtime1(8), vtime2(8), istop, lw
   integer :: ncore        ! number of cpu to be used with OpenMP
   logical :: bExist, bFail, filter_needed, Q_needed, Q_success, compute_stab
   real(kind=dp) :: debut, before, after, fin, duree_effective, Q_user
   character(len=250) :: cmdline
   character(len=180) :: argmnt
   character :: ddate*8, time*10, zone*5, fm*60
   character (len=:), allocatable :: WorkingDir, user_email

   read_PGM_P2 => read_PGM_P2_solver
   compute_stab = .true.
   keepAllFiles = .false.

   call date_and_time(values = vtime0)
   call get_command(cmdline)

   iarg = 1 ; call get_command_argument(iarg,argmnt)
   if (len_trim(argmnt) == 0) then
      write(error_unit,*) '>>>> ERROR: argument list is empty'
      stop ERR_ARGUMENT_LIST_IS_EMPTY
   else
      if (argmnt(1:2) == '-v') then
         write(output_unit,*) 'Solver_Appli - version '//trim(version_number)
         stop 0
      elseif (argmnt(1:2) == '-h') then
         write(output_unit,*) 'Solver_Appli - version '//trim(version_number)
         write(output_unit,*) 'Syntax : solver_appli [-k] [-s] <folder_name> [nb_cores] | -v | -h'
         write(output_unit,*) 'option -v : print the version number, then quit'
         write(output_unit,*) 'option -h : print this message, then quit'
         write(output_unit,*) 'option -k : keep all files generated during the computation'
         write(output_unit,*) 'option -s : skip image stabilisation step'
         stop 0
      else
         do while (argmnt(1:1) == '-')
            select case (argmnt(1:2))
            case ('-k')
                keepAllFiles = .true.
            case ('-s')
                compute_stab = .false.
            case ('-n')
                iarg = iarg+1 ; call get_command_argument(iarg,argmnt)
                if (len_trim(argmnt) > 0) then
                  read(argmnt,*) ncore
                else
                  ncore = 1
                endif
            case default
                write(output_unit,*)" unknown option ",argmnt(1:2)
            end select
            iarg = iarg+1 ; call get_command_argument(iarg,argmnt)
         enddo
         inquire (file=trim(argmnt)//'/.',exist=bExist)
         if (bExist) then
            allocate(character(len=len_trim(argmnt)) :: WorkingDir)
            WorkingDir = trim(argmnt)
            write(output_unit,*) 'The folder '//WorkingDir//' exist : OK!'
            iarg = iarg+1 ; call get_command_argument(iarg,argmnt)
            if (len_trim(argmnt) > 0) then
               read(argmnt,*) ncore
            else
               ncore = 1
#ifdef openmp
               ncore = omp_get_max_threads() / 2
#endif /* openmp */
            endif

            call cpu_time(debut)

            !opening the report file
            open(newunit=report_file,file=WorkingDir//'/solver_report.log',form='formatted',status='unknown')
            write(report_file,'(2a)') 'Execution report of Solver_Appli - version ',trim(version_number)
            call date_and_time(ddate,time,zone,values)
            fm = '(i4,a,i2.2,a,i2.2,a,i2.2,a,i2.2,a,i2.2)'
            write(simulation_date,fmt=fm) values(1),'-',values(2),'-',values(3),'T',values(5),':', &
                                                           values(6),':',values(7)
            write(report_file,'(/,2a)') 'Simulation date : ',trim(simulation_date)

            write(report_file,'(2a)') 'Command line : ',trim(cmdline)

            call create_dir_structure(WorkingDir,bfail)
            if (bFail) then
               write(error_unit,'(a)') '>>>> ERROR: data structure creation failed'
               write(report_file,'(a)') '>>>> ERROR: data structure creation failed'
               stop ERR_DATA_STRUCTURE_CREATION_FAILED
            endif
            call move_filesdat(WorkingDir) !move the *.dat user defined files in outputs.dir

            call get_environment_variable('PWD',pwd)
            call get_environment_variable('FLOWPIC_INSTALL_DIR',exedir)

            !--- Video sampling
            call date_and_time(values = vtime1)
            call video_sampling(WorkingDir,ncore,istop)
            if (istop /= 0) then
               write(error_unit,'(a)') '>>>> ERROR: video_sampling() failed !'
               write(report_file,'(a)') '>>>> ERROR: video_sampling() failed !'
               flush(error_unit) ; flush(output_unit)
               stop ERR_VIDEO_SAMPLING_FAILED
            else
               call date_and_time(values = vtime2)
               duree_effective = duration(vtime1,vtime2)
               write(output_unit,'(a,f11.3,a)') 'Total time for video sampling : ',duree_effective,' seconds'
               write(report_file,'(a,f11.3,a)') 'Total time for video sampling : ',duree_effective,' seconds'
            endif

            !---generating img_ref.dat - read GRP.dat
            call gen_img_ref(WorkingDir,istop)
            if (istop /= 0) then
               write(error_unit,'(a,i0,a)') '>>>> ERROR: generating img_ref failed (ffprobe with error code ',istop,')'
               write(report_file,'(a,i0,a)') '>>>> ERROR: generating img_ref failed (ffprobe with error code ',istop,')'
               stop ERR_GENERATING_IMG_REF_FAILED
            endif
            !---generating h.dat to make Fudaa-LSPIV happy when opening a saved project
            open(newunit=lw,file=trim(WorkingDir)//'/'//outputs_dir//'/'//h_dat,form='formatted',status='new')
            write(lw,'(a)') '0.0'
            close (lw)

            !--- Stabilisation
            call date_and_time(values = vtime1)
            call gen_mask(WorkingDir)
            call gen_stab_param(WorkingDir)
            call stabilisation(WorkingDir,ncore,istop,compute_stab)
            if (istop /= 0) then
               write(error_unit,'(a)') '>>>> ERROR: images stabilisation failed'
               write(report_file,'(a)') '>>>> ERROR: images stabilisation failed'
               stop ERR_IMAGES_STABILISATION_FAILED
            else
               call date_and_time(values = vtime2)
               duree_effective = duration(vtime1,vtime2)
               write(output_unit,'(a,f11.3,a)') 'Total time for stabilisation : ',duree_effective,' seconds'
               write(report_file,'(a,f11.3,a)') 'Total time for stabilisation : ',duree_effective,' seconds'
            endif

            !--- Orthorectification
            call date_and_time(values = vtime1)
            call cpu_time(before)
            call orthorectification(WorkingDir,ncore)
            call cpu_time(after)
            write(output_unit,'(a,f11.3,a)') 'CPU time for orthorectification : ',after-before,' seconds'
            write(report_file,'(a,f11.3,a)') 'CPU time for orthorectification : ',after-before,' seconds'
            call date_and_time(values = vtime2)
            duree_effective = duration(vtime1,vtime2)
            write(output_unit,'(a,f11.3,a)') 'Total time for orthorectification : ',duree_effective,' seconds'
            write(report_file,'(a,f11.3,a)') 'Total time for orthorectification : ',duree_effective,' seconds'

            !--- PIV
            call gen_PIV_param(WorkingDir)
            call gen_grid(WorkingDir)
            call date_and_time(values = vtime1)
            call cpu_time(before)
            call PIV(WorkingDir,ncore)
            call cpu_time(after)
            write(output_unit,'(a,f11.3,a)') 'CPU time for PIV : ',after-before,' seconds'
            write(report_file,'(a,f11.3,a)') 'CPU time for PIV : ',after-before,' seconds'
            call date_and_time(values = vtime2)
            duree_effective = duration(vtime1,vtime2)
            write(output_unit,'(a,f11.3,a)') 'Total time for PIV : ',duree_effective,' seconds'
            write(report_file,'(a,f11.3,a)') 'Total time for PIV : ',duree_effective,' seconds'

            !--- Post-processing
            call cpu_time(before)
            call gen_filter_dat(WorkingDir)
            write(output_unit,'(a)') '---> Filtering'
            write(report_file,'(a)') '---> Filtering'
            call sub_filter(WorkingDir//'/'//outputs_dir, WorkingDir)
            write(output_unit,'(a)') '---> Computing mean velocities'
            write(report_file,'(a)') '---> Computing mean velocities'
            call sub_moy_ec(WorkingDir//'/'//outputs_dir//'/', WorkingDir//'/'//outputs_dir//'/', WorkingDir//'/'//vel_filter//'/')
            !if user_transect does not exist we exit
            inquire(file=trim(WorkingDir)//'/'//outputs_dir//'/'//user_transect, exist=Q_needed)
            if (Q_needed) then
               write(output_unit,'(a)') '---> Computing discharge'
               write(report_file,'(a)') '---> Computing discharge'
               Q_user = Q_compute(WorkingDir)
               inquire(file=trim(WorkingDir)//'/'//outputs_dir//'/'//discharge,exist=Q_success)
            endif
            call cpu_time(after)
            write(output_unit,'(a,f11.3,a)') 'CPU time for filtering & mean velocities : ',after-before,' seconds'
            write(report_file,'(a,f11.3,a)') 'CPU time for filtering & mean velocities : ',after-before,' seconds'
            !write(output_unit,'(a,f11.3,a)') 'CPU time for filtering, mean velocities and discharge : ',after-before,' seconds'
            !write(report_file,'(a,f11.3,a)') 'CPU time for filtering, mean velocities and discharge : ',after-before,' seconds'

            !--- generating the result image
            call cpu_time(before)
            if (Q_needed .and. Q_success) then
               call gen_image_result(WorkingDir, Q_user)
            else
               call gen_image_result(WorkingDir)
            endif
            call cpu_time(after)
            write(output_unit,'(a,f11.3,a)') 'CPU time for results finalization : ',after-before,' seconds'
            write(report_file,'(a,f11.3,a)') 'CPU time for results finalization : ',after-before,' seconds'

            call date_and_time(values = vtime2)
            duree_effective = duration(vtime0,vtime2)
            write(output_unit,'(a,f11.3)') 'Actual calculation time before archiving : ',duree_effective
            write(report_file,'(a,f11.3)') 'Actual calculation time before archiving : ',duree_effective

            !--- archiving the results and emailing the results to the user
            call date_and_time(values = vtime1)
            call check_user_email(WorkingDir,user_email)
            if (Q_needed .and. Q_success) then
               call finalize_results(WorkingDir,user_email,istop,Q_user)
            else
               call finalize_results(WorkingDir,user_email,istop)
            endif

            !---Computational time
            call cpu_time(fin)
            write(output_unit,'(a,f11.3,a)') 'Total CPU time, without external programs : ',fin-debut,' seconds'

            call date_and_time(values = vtime2)
            duree_effective = duration(vtime0,vtime2)
            write(output_unit,'(a,f11.3)') 'Actual calculation time, including external programs : ',duree_effective
            if (istop /= 0) stop ERR_UNKNOWN_ERROR ; stop 0
         else
            write(error_unit,'(/,3a)') '>>>> ERROR: The folder '//trim(argmnt)//' does not exist. Bye.'
            stop ERR_FOLDER_DOES_NOT_EXIST
         endif
      endif
   endif
   stop 0

end program solver_appli


subroutine create_dir_structure(workdir,bfail)
!create all needed subdirs in the working directory
   use iso_fortran_env, only: error_unit, output_unit
   use global_solver_appli, only: report_file, final_results
   use lspiv_parameter, only: img_pgm, img_stab, img_transf, outputs_dir, transects, &
                              vel_filter, vel_raw, vel_real, &
                              vel_scal, run_external_program
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   logical, intent(out) :: bfail
   ! -- local variables --
   logical :: bExist
   character(len=:),allocatable :: command
   integer :: istop

   write(output_unit,'(/,2a)') '---> Creating folder structure in ',trim(workdir)
   write(report_file,'(/,2a)') '---> Creating folder structure in ',trim(workdir)

   inquire(file=trim(workdir)//'/'//img_pgm//'/.',exist=bExist)
   if (bExist) then
      write(error_unit,*) '>>>> ERROR: working directory already used'
      bfail = .true.
      return
   else
      allocate(character(len=len_trim(workdir)+113) :: command)
      write(command,'(a3,a,a9,10(1x,a))') 'cd ',trim(workdir),' && mkdir',img_pgm,img_stab,img_transf,outputs_dir,transects, &
                                                                            vel_filter,vel_raw,vel_real,vel_scal,final_results
      call run_external_program(command,.true.,istop)
      if (istop == 0) then
         bfail = .false.
      else
         bfail = .true.
         return
      endif
   endif
end subroutine create_dir_structure


subroutine move_filesdat(workdir)
!move the *.dat files into outputs.dir
   use global_solver_appli, only: ffmpeg_dat, user_velocity, user_transect
   use lspiv_parameter, only: run_external_program, flow_area, outputs_dir, grp, bathy, filters
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   ! -- local variables --
   character(len=:),allocatable :: command
   integer :: istop
   logical :: Q_needed, filter_needed

   allocate(character(len=len_trim(workdir)+11+19+17) :: command)
   !extraction
   write(command,'(2a)') 'cd '//trim(workdir),' && mv '//ffmpeg_dat//' '//outputs_dir
   istop = 0 ; call run_external_program(command,.true.,istop)
   !stabilisation
   write(command,'(2a)') 'cd '//trim(workdir),' && mv '//flow_area//' '//outputs_dir
   istop = 0 ; call run_external_program(command,.true.,istop)
   !orthorectification
   write(command,'(2a)') 'cd '//trim(workdir),' && mv '//GRP//' '//outputs_dir
   istop = 0 ; call run_external_program(command,.true.,istop)
   !PIV
   write(command,'(2a)') 'cd '//trim(workdir),' && mv '//user_velocity//' '//outputs_dir
   istop = 0 ; call run_external_program(command,.true.,istop)
   !filters
   inquire(file=trim(workdir)//'/'//filters, exist=filter_needed)
   if (filter_needed) then
      write(command,'(2a)') 'cd '//trim(workdir),' && mv '//filters//' '//outputs_dir
      istop = 0 ; call run_external_program(command,.true.,istop)
   endif
   !bathy
   inquire(file=trim(workdir)//'/'//user_transect, exist=Q_needed)
   if (Q_needed) then
      write(command,'(2a)') 'cd '//trim(workdir),' && mv '//user_transect//' '//outputs_dir
      istop = 0 ; call run_external_program(command,.true.,istop)
   endif
end subroutine move_filesdat


subroutine video_sampling(workdir,ncore,istop)
!images extraction from the video
!need a video file named video
   use iso_fortran_env, only: error_unit, output_unit
   use errors, only: ERR_IMAGE_EXTRACTION
   use global_solver_appli, only: report_file, ffmpeg_dat, nb_images
   use lspiv_parameter, only: run_external_program, outputs_dir, img_pgm
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   integer, intent(in) :: ncore
   integer, intent(out) :: istop
   ! -- local variables --
   character (len=:), allocatable :: command
   integer :: lu, ios
   character(len=1000) :: ligne
   integer :: t0, dt, n, k
   character(len=13) :: nom
   logical :: b_fail, b_exist

   write(output_unit,'(/,a)') '---> video sampling'
   write(report_file,'(/,a)') '---> video sampling'

   !read parameter file
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//ffmpeg_dat,form='formatted',status='old')
   read(lu,*) t0 !start time in secondes (integer)
   read(lu,*) dt !duration time in secondes (integer)
   read(lu,*) n  !periodicity: one keeps 1/n images
   close (lu)

   call write_progression(workdir,'Step 1 -- images extraction from video')

   !running ffmpeg with log captured in ffmpeg.log
   allocate(character(len=3*len_trim(workdir)+120) :: command)
   write(command,'(3a,i2.2,a,i0,a,i0,a)') 'ffmpeg -i ',trim(workdir)//'/video',' -vf framestep=',n,' -ss ',t0,' -to ',t0+dt, &
                         ' '//trim(workdir)//'/'//img_pgm//'/'//'image%4d.pgm 2>&1 |tee -i '//trim(workdir)//'/ffmpeg.log'
   write(report_file,'(2a)') 'ffmpeg command: ',trim(command)
   istop = 0 ; call run_external_program('cd '//trim(workdir),.true.,istop)
   istop = 0 ; call run_external_program(command,.true.,istop)
   istop = 0 ; call run_external_program('cd -',.true.,istop)

   !copying ffmpeg.log in report file
   open(newunit=lu,file=trim(workdir)//'/ffmpeg.log',form='formatted',status='old')
   do
      read(lu,'(a)',iostat=ios) ligne
      if (ios /= 0) exit
      write(report_file,'(a)') trim(ligne)
      if (ligne(1:6) == 'frame=') read(ligne(7:11),'(i5)') nb_images
   enddo
   close (lu,status='delete')
   flush(unit=report_file)

   if (istop /= 0) then
      write(error_unit,'(a,i0)') 'ERROR ffmpeg: images extraction from video failed with error code ',istop
      return !images extraction failed nothing else to do.
   endif

   !vérification de la liste des images extraites
   b_fail = .false.
   do k = 1, nb_images
      write(nom,'(a5,i4.4,a4)') 'image',k,'.pgm'
      inquire(file=trim(workdir)//'/'//img_pgm//'/'//nom, exist=b_exist)
      b_fail = b_fail .or. .not.b_exist
   enddo
   if (b_fail) then
      write(output_unit,'(a)') '>>>> ERROR: something went wrong during the image extraction :'
      write(output_unit,'(12x,a,i0)') 'the number of images from ffmpeg is greater than the actual number of images : ',nb_images
      write(error_unit,'(a)') '>>>> ERROR: something went wrong during the image extraction :'
      write(error_unit,'(12x,a,i0)') 'the number of images from ffmpeg is greater than the actual number of images : ',nb_images
      write(report_file,'(a)') '>>>> ERROR: something went wrong during the image extraction :'
      write(report_file,'(12x,a,i0)') 'the number of images from ffmpeg is greater than the actual number of images : ',nb_images
      stop ERR_IMAGE_EXTRACTION
   else
      write(output_unit,'(a,i0,a)') '----> Verification images list : OK (',nb_images,' images)'
      write(report_file,'(a,i0,a)') '----> Verification images list : OK (',nb_images,' images)'
   endif

   !conversion PGM P5 -> PGM P2
   write(output_unit,'(a)') '---> conversion from PGM P5 to PGM P2'
   write(report_file,'(a)') '---> conversion from PGM P5 to PGM P2'
   call convert_P2(workdir,img_pgm,ncore,1)

   flush(unit=report_file)
end subroutine video_sampling


subroutine convert_P2(workdir,subdir,ncore,iStep)
! converting from PGM P5 to PGM P2 using ncore CPU
   use global_solver_appli, only: report_file, nb_images
   use lspiv_parameter, only: read_last_line, run_external_program
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   character (len=*), intent(in) :: subdir     !sub-directory
   integer, intent(in) :: ncore, iStep
   ! -- local variables --
   character (len=:), allocatable :: command
   integer :: lu, k, num, ios, istop
   character(len=120) :: ligne, last_line, p_message

   allocate(character(len=len_trim(workdir)+len_trim(subdir)+130) :: command)
   !running the command asynchronously
   write(command,'(a,i0,a)') 'cd '//trim(workdir)//'/'//trim(subdir)//' && ls *.pgm | xargs -n 1 -P ',ncore, &
                             ' -I{} convert {} -identify -compress none {} 2>&1 |tee -i ../tmp.log && echo End >> ../tmp.log'
   write(report_file,'(2a)') 'convert command: ',trim(command)
   call run_external_program(command,.false.,istop)  !asynchronous

   !monitoring external program progression
   call sleep(1)  !waiting the program has started
   open(newunit=lu,file=trim(workdir)//'/tmp.log',form='formatted',status='old')
   last_line = ''
   do
      call read_last_line(lu,last_line)
      if (last_line(1:3) == 'End') exit
      call sleep(1)
      k = scan(last_line,'.') - 1
      read(last_line(6:k),'(i4)') num
      write(p_message,'(a,i0,a,f0.1,a)') 'Step ',iStep,' -- Conversion to PGM P2 : ',real(num)/real(nb_images)*100.,'%'
      call write_progression(workdir,p_message)
      rewind(lu)
   enddo
   !copying tmp.log in report file
   rewind(lu)
   do
      read(lu,'(a)',iostat=ios) ligne
      if (ios /= 0) exit
      if (ligne(1:3) /= 'End') write(report_file,'(a)') trim(ligne)
   enddo
   close(lu,status='delete')

end subroutine convert_P2


subroutine gen_img_ref(workdir,istop)
! generate img_ref.dat from GRP.dat and ffprobe output
   use iso_fortran_env, only: error_unit, output_unit
   use errors, only: ERR_NOT_ENOUGH_POINTS_IN_GRP_FILE, ERR_COMPUTING_COEF
   use mod_ortho, only: sub_ortho, estimated_resolution, compute_XY, compute_XY_2D, compute_XY_3D, compute_A_coeff, compute_XY
   use global_solver_appli, only: report_file, fps, time_length, resolution, video_creation_time
   use lspiv_parameter, only: dp, outputs_dir, GRP, img_ref, coeff_dat, run_external_program
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   integer,intent(out) :: istop
   ! -- local variables --
   character (len=:), allocatable :: command, GRP_dat, coeff_file
   integer :: lu, ios, ni, nj, nb_frame, nb_points, n, rotation, ix, jy, nbc
   character (len=80) :: ligne
   real(kind=dp) :: xmin, ymin, xmax, ymax, x, y, z, a(9)
   logical :: bExist

   write(output_unit,'(a)') '---> Generating img_ref.dat'
   write(report_file,'(a)') '---> Generating img_ref.dat'

   !using ffprobe to get width, height and fps
   allocate(character(len=len_trim(workdir)+150) :: command)
   write(command,'(4a)') 'ffprobe -v error -select_streams v:0 -show_streams -show_entries stream_tags=creation_time ', &
                         '-of default=noprint_wrappers=1 ', trim(workdir)//'/'//'video', ' > ffprobe.log'
   write(report_file,'(a)') 'ffprobe command : '//trim(command)
!    istop = 0 ; call run_external_program('cd '//trim(workdir),.true.,istop)
   istop = 0 ; call run_external_program(command,.true.,istop)
   if (istop /= 0) return  !ffprobe failed with error code istop

   open(newunit=lu,file='ffprobe.log',form='formatted',status='old')
   do
      read(lu,'(a)',iostat=ios) ligne
      if (ios /= 0) exit
      if (ligne(1:6)  == 'width=')     read(ligne(7:),*) ni
      if (ligne(1:7)  == 'height=')    read(ligne(8:),*) nj
      if (ligne(1:9)  == 'duration=')  read(ligne(10:),*) time_length
      if (ligne(1:10) == 'nb_frames=') read(ligne(11:),*) nb_frame
      if (ligne(1:18) == 'TAG:creation_time=') video_creation_time = ligne(19:37)
      if (ligne(1:9)  == 'rotation=')  then
         read(ligne(10:),*) rotation
         exit
      endif
   enddo
   close(lu,status='delete')
!    istop = 0 ; call run_external_program('cd -',.true.,istop)
   !print video metadata from ffprobe on report file
   write(report_file,'(a)') 'Video metadata reported by ffprobe:'
   write(report_file,'(a,i0)')   'width         = ',ni
   write(report_file,'(a,i0)')   'height        = ',nj
   write(report_file,'(a,f0.3)') 'duration      = ',time_length
   write(report_file,'(a,i0)')   'nb_frames     = ',nb_frame
   write(report_file,'(a,i0)')   'rotation      = ',rotation
   write(report_file,'(2a)')     'creation_time = ',video_creation_time


   fps = real(nb_frame,kind=dp) / time_length
   if (abs(rotation) == 90) then  ! video has been rotated
      ios = ni ; ni = nj ; nj = ios
   endif

   !reading GRP.dat to get xmin, ymin, xmax, ymax
   allocate(character(len=len_trim(workdir)+20) :: GRP_dat)
   GRP_dat = trim(workdir)//'/'//outputs_dir//'/'//GRP
   xmin = 1.e+30_dp  ;  xmax = -1.e+30_dp  ;  ymin = 1.e+30_dp  ;  ymax = -1.e+30_dp
   open(newunit=lu,file=trim(GRP_dat),form='formatted',status='old')
   read(lu,*)
   read(lu,*) nb_points
   read(lu,*)
   do n = 1, nb_points
      read(lu,*) x, y, z, ix, jy
      xmin = min(x,xmin)  ;  xmax = max(x,xmax)
      ymin = min(y,ymin)  ;  ymax = max(y,ymax)
   enddo
   close (lu)

   !computing resolution
   if (nb_points < 4) then
      write(output_unit,'(a)') '>>>> ERROR : not enough points in GRP.dat file'
      write(report_file,'(a)') '>>>> ERROR: not enough points in GRP.dat file'
      write(error_unit,'(a)') '>>>> ERROR : not enough points in GRP.dat file'
      stop ERR_NOT_ENOUGH_POINTS_IN_GRP_FILE
   endif

   !check if coeff.dat exists. If it does not, then launch sub_ortho()
   allocate(character(len=len_trim(workdir)+22) :: coeff_file)
   coeff_file = trim(workdir)//'/'//outputs_dir//'/'//coeff_dat
   inquire(file=trim(coeff_file),exist=bExist)
   if (.not.bExist) then
      call sub_ortho(trim(workdir)//'/'//outputs_dir)
   endif

   call compute_A_coeff(coeff_file,a,nbc)
   select case (nbc)
      case (8) ; compute_XY => compute_XY_2D
      case (11) ; compute_XY => compute_XY_3D
      case default
         write(error_unit,'(a,i0)') '>>>> ERROR computing A coeff ; nbc not equal to 8 or 11 : ',nbc
         stop ERR_COMPUTING_COEF
   end select

   resolution = estimated_resolution(GRP_dat,ni,nj,a)
   write(report_file,'(a,f6.4)') '>>> Resolution from convex hull of GRP : ',resolution

   !writing img_ref.dat
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//img_ref,form='formatted',status='new')
   write(lu,'(a)') 'xmin,ymin'
   write(lu,'(f6.1,1x,f6.1)') xmin, ymin
   write(lu,'(a)') 'xmax,ymax'
   write(lu,'(f6.1,1x,f6.1)') xmax, ymax
   write(lu,'(a)') 'resolution'
   write(lu,'(f6.4)') resolution
   write(lu,'(a)') 'size of raw images: height - width'
   write(lu,'(i0,1x,i0)') nj, ni
   close (lu)

   flush(report_file)
end subroutine gen_img_ref


subroutine gen_mask(workdir)
! generate mask.dat from flow area
   use iso_fortran_env, only: output_unit
   use global_solver_appli, only: report_file, final_results
   use lspiv_parameter, only: flow_area, point2D, is_inside, run_external_program, &
                              dp, outputs_dir, img_transf, img_pgm, read_img_ref
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   ! -- local variables --
   character (len=:), allocatable :: command
   character (len=14) :: script = 'mask.gnu'
   integer :: lw, nb, i, j, ni, nj, istop, ni0, nj0
   type (point2D), allocatable :: p(:)
   type (point2D) :: xy
   real(kind=dp) :: xmin, ymin, xmax, ymax, r

   write(output_unit,'(a)') '---> Generating mask.dat'
   write(report_file,'(a)') '---> Generating mask.dat'
   call write_progression(workdir,'Step 2 -- Computing flow area')

   !open and read flow area file
   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//flow_area,status='old')
   read(lw,*) Nb
   allocate(p(Nb+1))  !Nb+1 is necessary in case the polygon is not closed and we have to add a point
   i = 1
   read(lw,*) ni, nj  !width - height
   p(i) = point2D(x=real(ni,kind=dp),y=real(nj,kind=dp))
   ni0 = ni  ;  nj0 = nj
   do i = 2, Nb
      read(lw,*) ni, nj
      p(i) = point2D(x=real(ni,kind=dp),y=real(nj,kind=dp))
   enddo
   if (ni /= ni0 .or. nj /= nj0) then
      !adding one point to close the polygon
      Nb = Nb+1
      p(Nb) = p(1)
   endif
   rewind(lw)
   write(lw,'(i0)') Nb
   do i = 1, Nb-1
      write(lw,'(i0,1x,i0,1x,a,i0)') int(p(i)%x), int(p(i)%y), 'P', i
   enddo
   write(lw,'(i0,1x,i0,1x,a)') int(p(1)%x), int(p(1)%y), 'P1'
   close(lw)

   !image size
   call read_img_ref(trim(workdir)//'/'//outputs_dir,xmin, ymin, xmax, ymax, r, ni, nj)

   !generate the mask
   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//'mask.dat',form='formatted',status='new')
   do j = 1, nj
      xy%y = real(j-1,kind=dp)
      do i = 1, ni
         xy%x = real(i-1,kind=dp)
         if (is_inside(xy,p,nb)) write(lw,'(i0,1x,i0)') j,i
      enddo
   enddo
   close (lw)

   !generate a control image which show the first raw image, the polygon and the mask
   write(output_unit,'(a)')'---> Generating the control image'
   write(report_file,'(a)')'---> Generating the control image'

   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//script,form='formatted',status='new')
   write(lw,'(a)') 'reset'
   write(lw,'(a,i0,a1,i0)') 'set term png size ',ni,',',nj
   write(lw,'(3a)') 'set output "flow_area_control.png"'
   write(lw,'(a)') 'set multiplot'
   !As the background picture's size is nj x ni, we choose xrange and yrange of these values
   write(lw,'(a,i0,a1)') 'set xrange [0:',ni-1,']'
   write(lw,'(a,i0,a1)') 'set yrange [0:',nj-1,']'
   write(lw,'(a)') 'unset tics'
   write(lw,'(a)') 'unset border'
   !Plot the background image
   write(lw,'(a)') 'plot "image.png" binary filetype=png with rgbimage'
   !Plot the mask
   write(lw,'(a,i0,a1)') 'set xrange [0:',ni-1,']'
   write(lw,'(a,i0,a)') 'set yrange [',nj-1,':0]'
   write(lw,'(a)') 'plot "mask.dat" using 2:1 notitle lc rgb "red"'
   !Plot the polygon
   write(lw,'(3a)') 'plot "',flow_area,'" using 1:2 notitle with lines lw 3 lc rgb "green"'
   write(lw,'(3a)') 'plot "',flow_area,'" using 1:2:3 notitle with labels point offset character 1, character 0.5 tc rgb "green"'
   write(lw,'(a)') 'unset multiplot'
   close(lw)

   allocate(character(len=2*len_trim(workdir)+len_trim(img_transf)+len_trim(final_results)+len_trim(outputs_dir)+43) :: command)
   ! conversion image0001_transf.pgm into image.png
   write(command,'(2a,1x,a)') 'convert ',trim(workdir)//'/'//img_pgm//'/'//'image0001.pgm', &
                                   trim(workdir)//'/'//outputs_dir//'/'//'image.png'
   istop = 0 ; call run_external_program(command,.true.,istop)
   ! run gnuplot script
   write(command,'(4a)') 'cd ',trim(workdir)//'/'//outputs_dir,' && gnuplot ',script
   istop = 0 ; call run_external_program(command,.true.,istop)
   ! remove temporary files
   write(command,'(a)') 'rm '//trim(workdir)//'/'//outputs_dir//'/'//'image.png'
   istop = 0 ; call run_external_program(command,.true.,istop)
   write(command,'(a)') 'rm '//trim(workdir)//'/'//outputs_dir//'/'//script
   istop = 0 ; call run_external_program(command,.true.,istop)
end subroutine gen_mask


subroutine gen_grid(workdir)
! generate grid.dat from GRP
   use iso_fortran_env, only: error_unit, output_unit
   use errors, only: ERR_ORTHORECTIFICATION_NOT_2D
   use lspiv_parameter, only: dp, outputs_dir, GRP, grid, read_coeff_ortho
   use global_solver_appli, only: report_file, resolution, grid_step
   use lspiv_parameter, only: point2D, is_inside, flow_area
   use mod_ortho, only: ortho_rectif
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   ! -- local variables --
   real(kind=dp), parameter :: n_grid = 24._dp
   integer :: lu, i, j, n, Nb, ni, nj, lw, di, dj, nb_points, x0, y0, ni0, nj0
   real(kind=dp) :: a(11), x, y, z
   type (point2D) :: pt
   type (point2D), allocatable :: r(:), rt(:), p(:), q(:)

   write(output_unit,'(a)') '---> Generating grid.dat'
   write(report_file,'(a)') '---> Generating grid.dat'

   !reading GRP.dat to get xmin, ymin, xmax, ymax
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//GRP,form='formatted',status='old')
   read(lu,*)
   read(lu,*) nb_points
   read(lu,*)
   allocate (r(nb_points),rt(nb_points))
   do n = 1, nb_points
      read(lu,*) x, y, z, r(n)%x, r(n)%y
   enddo
   close (lu)

   !image coordinates of the vertices of the rectangle in the ortho-image
   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//'GRP_ortho.dat',form='formatted',status='new')
   call read_coeff_ortho(trim(workdir)//'/'//outputs_dir,n,a)
   if (n /= 8) then
      write(output_unit,'(a)') '>>>> ERROR: this version works only with orthorectification 2D'
      write(report_file,'(a)') '>>>> ERROR: this version works only with orthorectification 2D'
      write(error_unit,'(a)') '>>>> ERROR: this version works only with orthorectification 2D'
      stop ERR_ORTHORECTIFICATION_NOT_2D
   endif
   do i = 1, nb_points
      rt(i) = ortho_rectif(r(i),a,resolution)
   enddo
   write(output_unit,*) ''
   write(output_unit,*) 'GRP raw and orthorectified'
   write(report_file,*) ''
   write(report_file,*) 'GRP raw and orthorectified'
   write(lw,*) nb_points
   do i = 1, nb_points
      write(output_unit,*) int(r(i)%x),int(r(i)%y),int(rt(i)%x),int(rt(i)%y)
      write(report_file,*) int(r(i)%x),int(r(i)%y),int(rt(i)%x),int(rt(i)%y)
      write(lw,'(i0,1x,i0,1x,a,i0)') int(rt(i)%x),int(rt(i)%y),'P',i
   enddo
   close (lw)

   !read the flow area
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//flow_area,status='old')
   read(lu,*) Nb
   allocate(p(Nb+1),q(Nb+1))   !Nb+1 is necessary in case the polygon is not closed and we have to add a point
   i = 1
   read(lu,*) nj, ni
   p(i) = point2D(x=real(nj,kind=dp),y=real(ni,kind=dp))
   ni0 = ni  ;  nj0 = nj
   do i = 2, Nb
      read(lu,*) nj, ni
      p(i) = point2D(x=real(nj,kind=dp),y=real(ni,kind=dp))
   enddo
   close(lu)
!   if (int(p(Nb)%x) /= int(p(1)%x) .and. int(p(Nb)%y) /= int(p(1)%y)) then
   if (ni /= ni0 .and. nj /= nj0) then
      Nb = Nb + 1
      p(Nb) = p(1)
   endif
   !projection of flow area onto the ortho-image
   write(output_unit,*) ''
   write(output_unit,*) 'Flow area polygon raw and orthorectified'
   write(report_file,*) ''
   write(report_file,*) 'Flow area polygon raw and orthorectified'
   do i = 1, Nb
      q(i) = ortho_rectif(p(i),a,resolution)
      write(output_unit,'(4i12,a2,i0)') int(p(i)%x),int(p(i)%y),int(q(i)%x),int(q(i)%y),' P',i
      write(report_file,'(4i12,a2,i0)') int(p(i)%x),int(p(i)%y),int(q(i)%x),int(q(i)%y),' P',i
   enddo
   close (lu)

   !generating the grid 24 x 24
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//grid,form='formatted',status='new')
   di = int(abs(rt(2)%x - rt(1)%x) / n_grid)
   dj = int(abs(rt(3)%y - rt(2)%y) / n_grid)
   write(output_unit,*) di,dj
   x0 = int((abs(rt(2)%x - rt(1)%x) - n_grid*real(di,kind=dp)) / 2._dp)
   y0 = int((abs(rt(3)%y - rt(2)%y) - n_grid*real(dj,kind=dp)) / 2._dp)
   do j = nint(n_grid)-1, 1, -1  !we remove the first and last columns and rows which are to close to the border
      do i = 1, nint(n_grid)-1
         pt = point2D(x=x0+i*di,y=y0+j*dj)
         if (is_inside(pt,q,Nb)) then
            write(lu,'(i0,1x,i0)') int(pt%x),int(pt%y)
         endif
      enddo
   enddo
   close (lu)
   grid_step%x = di*resolution  ;  grid_step%y = dj*resolution
end subroutine gen_grid


subroutine gen_stab_param(workdir)
! generate grid.dat from GRP
   use global_solver_appli, only: stab_param
   use lspiv_parameter, only: outputs_dir
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   ! -- local variables --
   integer :: lu

   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//stab_param,form='formatted',status='new')
   write(lu,'(a)') 'Keypoints density (0: Low, 1: Medium, 2: High)'
   write(lu,'(a)') '1'
   write(lu,'(a)') 'Transformation model (0: Projective, 1: Similarity)'
   write(lu,'(a)') '1'
   close (lu)
end subroutine gen_stab_param


subroutine stabilisation(workdir,ncore,istop,compute_stab)
!Run stabilisation program
   use iso_fortran_env, only: error_unit, output_unit
   use global_solver_appli, only: pwd, report_file, nb_images, exedir
   use lspiv_parameter, only: run_external_program, img_stab
   use pipes_module
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   integer,intent(in) :: ncore
   integer,intent(out) :: istop
   logical,intent(in)  :: compute_stab
   ! -- local variables --
   character (len=:), allocatable :: command
   integer :: ios, j, n, i
   character(len=:), allocatable :: nom
   logical :: bexist
   integer,parameter :: buffer_length = 1000
   type(c_ptr) :: h
   character(kind=c_char,len=buffer_length) :: line
   character(len=80) :: p_message
   character(len=80) :: p_message2

   if(compute_stab)then
      write(output_unit,'(a)') '---> Running images stabilisation'
      write(report_file,'(a)') '---> Running images stabilisation'

      !launch stab_image
      allocate(character(len=2*len_trim(workdir)+len_trim(exedir)+100) :: command)
      write(command,'(a,i2.2,2a)') 'export OMP_NUM_THREADS=',ncore,' && cd '//trim(workdir), &
                                    ' && '//trim(exedir)//'/stab_image 2>&1 '//c_null_char
      write(report_file,'(2a)') 'stab_image command: ',trim(command)
      h = c_null_ptr
      h = popen(command,'r'//c_null_char)

      if (c_associated(h)) then
        do while (c_associated(fgets(line,buffer_length,h)))
    !        ligne = ligne//c2f_string(line)//c_new_line
          write(p_message2,'(a)') c2f_string(line)
          write(output_unit,'(a)') p_message2
          write(report_file,'(a)') p_message2
          i=index(p_message2,"%")
          if(i .gt. 0)then
              write(p_message,'(2a)') 'Step 2 -- Stabilisation : ',p_message2(1:i)
              call write_progression(workdir,p_message)
          end if
        end do
        ios = pclose(h)
      end if

      allocate(character(len=len_trim(workdir)+len_trim(img_stab)+20) :: nom)
      n = 0
      !counting the number of processed images
      do j = 1, nb_images
          write(nom,'(a,i4.4,a)') trim(workdir)//'/'//trim(img_stab)//'/'//'image',j,'_stab.pgm'
          inquire(file=nom,exist=bexist)
          if (bexist) n = n+1
      enddo

      if (n == nb_images) then
          istop = 0
      else
          !stab_image crashed
          istop = 1
          write(output_unit,'(a,i0)')'ERROR stab_image: images stabilisation failed (error code unavailable)'
          write(error_unit,'(a,i0)')'ERROR stab_image: images stabilisation failed (error code unavailable) '
          return !stabilisation failed, nothing else to do!
      endif
   else
      write(output_unit,'(a)') '---> Skipping images stabilisation'
      write(report_file,'(a)') '---> Skipping images stabilisation'
      allocate(character(len=2*len_trim(workdir)+len_trim(img_stab)+100) :: command)
      do j = 1, nb_images
         write(command,'(a,i4.4,a,i4.4,a)') 'cp '//trim(workdir)//'/img_pgm/image',j,'.pgm '//&
         trim(workdir)//'/'//trim(img_stab)//'/'//'image',j,'_stab.pgm'
         call execute_command_line(command)
      enddo
      istop = 0
   endif
   deallocate(command)
   flush(unit=report_file)
end subroutine stabilisation


subroutine orthorectification(workdir,ncore)
! routine d'orthorectification par lot
! la parallélisation concerne la boucle sur les images.
! l'orthorectification proprement dite est trop courte pour que la parallélisation apporte vraiment quelque chose.
   use iso_fortran_env, only: error_unit, output_unit
   use errors, only: ERR_SUB_TRANSF_IMG_2D_FAILED, ERR_SUB_TRANSF_IMG_3D_FAILED, ERR_SUB_TRANSF_IMG_0_FAILED
   use omp_lib, only: omp_get_thread_num
   use lspiv_parameter, only: dp, outputs_dir, img_stab, img_transf, h_dat, &
                                 read_img_ref, read_coeff_ortho
   use global_solver_appli, only: report_file, nb_images
   use mod_transf_23D, only: sub_transf_img_0, sub_transf_img_3D, sub_transf_img_2D
   use mod_ortho, only: sub_ortho
   use mod_verif_ortho, only: sub_verif_ortho
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   integer,intent(inout) :: ncore
   ! -- local variables --
   integer :: lu, n
   character(len=18) :: image
   character(len=:), allocatable :: image_in, image_out
!   character(len=1000) :: image_in, image_out
   real(kind=dp) :: xmin, xmax, ymin, ymax, r, a(11), h
   integer :: ni, nj, nb, istop, nseq, width, height
   integer :: length_in, length_out
   integer :: compteur
   character(len=120) :: p_message

   write(output_unit,'(a)') '---> Orthorectification'
   write(report_file,'(a)') '---> Orthorectification'

   write(output_unit,'(a)') '------> Compute ortho-rectification parameters'
   write(report_file,'(a)') '------> Compute ortho-rectification parameters'
   call sub_ortho(trim(workdir)//'/'//outputs_dir)
   write(output_unit,'(a)') '------> Check ortho-rectification parameters - results in GRP_test_ortho.dat'
   write(report_file,'(a)') '------> Check ortho-rectification parameters - results in GRP_test_ortho.dat'
   call sub_verif_ortho(trim(workdir)//'/'//outputs_dir)

   call read_img_ref(trim(workdir)//'/'//outputs_dir,xmin,ymin,xmax,ymax,r,width,height)
   ni = height ; nj = width !matrix view : i,ni -> row ; j,nj -> column
   call read_coeff_ortho(trim(workdir)//'/'//outputs_dir,nb,a)
   length_in = len_trim(workdir)+len_trim(img_stab)+20
   length_out = len_trim(workdir)+len_trim(img_transf)+22
   compteur = 0
   nseq = 1
   if (nb == 8) then  !2D orthorectification
!$omp parallel default(private) &
   !$omp shared(workdir,report_file,nb_images,nb,a,xmin,xmax,ymin,ymax,r,ni,nj,compteur,nseq,length_in,length_out) &
   !$omp num_threads(ncore)
!$omp do
       do n = 1, nb_images
         write(image,'(a5,i4.4,a9)') 'image',n,'_stab.pgm'
#ifdef openmp
         write(report_file,'(3a,i0)') 'Orthorectification 2D of ',trim(image),' with core ',omp_get_thread_num()
#endif /* openmp */
#ifndef openmp
         write(report_file,'(2a)') 'Orthorectification 2D of ',trim(image)
#endif /* openmp */
         allocate(character(len=length_in) :: image_in)
         image_in = trim(workdir)//'/'//img_stab//'/'//image
         allocate(character(len=length_out) :: image_out)
         image_out = trim(workdir)//'/'//img_transf//'/'//image(1:9)//'_transf.pgm'
         call sub_transf_img_2D(a,xmin,ymin,xmax,ymax,r,ni,nj,image_in,image_out,nseq,istop)
         if (istop /= 0) then
            write(error_unit,'(a,i0)') '>>>> ERROR : sub_transf_img_2D() failed with error code ',istop
            write(output_unit,'(a,i0)') '>>>> ERROR : sub_transf_img_2D() failed with error code ',istop
            write(report_file,'(a,i0)') '>>>> ERROR : sub_transf_img_2D() failed with error code ',istop
            flush(report_file)
            stop ERR_SUB_TRANSF_IMG_2D_FAILED
         else
            deallocate (image_in, image_out)
         endif
         compteur = compteur + 1
         write(output_unit,'(a,i0,a,i0,a)') 'Orthorectification 2D : ',compteur,'/',nb_images,' images'
         write(p_message,'(a,f0.1,a)') 'Step 3 -- Orthorectification 2D : ',real(compteur)/real(nb_images)*100.,'%'
         call write_progression(workdir,p_message)
      enddo
!$omp end do
!$omp end parallel
   elseif (nb == 11) then  !3D orthorectification
      open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//h_dat,form='formatted',status='old')
      read(lu,*) h
!$omp parallel default(private) &
   !$omp shared(workdir,report_file,nb_images,nb,a,xmin,xmax,ymin,ymax,r,ni,nj,compteur,nseq) &
   !$omp num_threads(ncore)
!$omp do
       do n = 1, nb_images
         write(image,'(a5,i4.4,a9)') 'image',n,'_stab.pgm'
#ifdef openmp
         write(report_file,'(3a,i0)') 'Orthorectification 3D of ',trim(image),' with core ',omp_get_thread_num()
#endif /* openmp */
#ifndef openmp
         write(report_file,'(2a)') 'Orthorectification 3D of ',trim(image)
#endif /* openmp */
         allocate(character(len=length_in) :: image_in)
         image_in = trim(workdir)//'/'//img_stab//'/'//image
         allocate(character(len=length_out) :: image_out)
         image_out = trim(workdir)//'/'//img_transf//'/'//image(1:9)//'_transf.pgm'
         call sub_transf_img_3D(a,h,xmin,ymin,xmax,ymax,r,ni,nj,image_in,image_out,nseq,istop)
         if (istop /= 0) then
            write(error_unit,'(a,i0)') '>>>> ERROR : sub_transf_img_3D() failed with error code ',istop
            write(output_unit,'(a,i0)') '>>>> ERROR : sub_transf_img_3D() failed with error code ',istop
            write(report_file,'(a,i0)') '>>>> ERROR : sub_transf_img_3D() failed with error code ',istop
            flush(report_file)
            stop ERR_SUB_TRANSF_IMG_3D_FAILED
         else
            deallocate (image_in, image_out)
         endif
         compteur = compteur + 1
         write(output_unit,'(a,i0,a,i0,a)') 'Orthorectification 3D : ',compteur,'/',nb_images,' images'
         write(p_message,'(a,f0.1,a)') 'Step 3 -- Orthorectification 3D : ',real(compteur)/real(nb_images)*100.,'%'
         call write_progression(workdir,p_message)
      enddo
!$omp end do
!$omp end parallel
   else  !no orthorectification
!$omp parallel default(private) shared(workdir,report_file,nb_images,nb,a,xmin,xmax,ymin,ymax,r,ni,nj) num_threads(ncore)
!$omp do
       do n = 1, nb_images
         write(image,'(a5,i4.4,a9)') 'image',n,'_stab.pgm'
#ifdef openmp
         write(report_file,'(3a,i0)') 'Orthorectification (none) of ',trim(image),' with core ',omp_get_thread_num()
#endif /* openmp */
#ifndef openmp
         write(report_file,'(2a)') 'Orthorectification (none) of ',trim(image)
#endif /* openmp */
         allocate(character(len=length_in) :: image_in)
         image_in = trim(workdir)//'/'//img_stab//'/'//image
         allocate(character(len=length_out) :: image_out)
         image_out = trim(workdir)//'/'//img_transf//'/'//image(1:9)//'_transf.pgm'
         call sub_transf_img_0(a,xmin,ymin,xmax,ymax,r,ni,nj,image_in,image_out,nseq,istop)
         if (istop /= 0) then
            write(error_unit,'(a,i0)') '>>>> ERROR : sub_transf_img_0() failed with error code ',istop
            write(output_unit,'(a,i0)') '>>>> ERROR : sub_transf_img_0() failed with error code ',istop
            write(report_file,'(a,i0)') '>>>> ERROR : sub_transf_img_0() failed with error code ',istop
            flush(report_file)
            stop ERR_SUB_TRANSF_IMG_0_FAILED
         else
            deallocate (image_in, image_out)
         endif
         compteur = compteur + 1
         write(output_unit,'(a,i0,a,i0,a)') 'Orthorectification (none) : ',compteur,'/',nb_images,' images'
         write(p_message,'(a,f0.1,a)') 'Step 3 -- Orthorectification (none) : ',real(compteur)/real(nb_images)*100.,'%'
         call write_progression(workdir,p_message)
     enddo
!$omp end do
!$omp end parallel
   endif
end subroutine orthorectification


subroutine gen_filter_dat(workdir)
! generate filters.dat
   use iso_fortran_env, only: error_unit, output_unit
   use lspiv_parameter, only: dp, outputs_dir, filters
   use global_solver_appli, only: report_file
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   ! -- local variables --
   integer :: lu

   write(output_unit,'(a)') '---> Generating filters.dat'
   write(report_file,'(a)') '---> Generating filters.dat'

   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//filters,form='formatted',status='new')
   write(lu,*)"# V1.0 Filter parameters"
   write(lu,*)"# Correlation (active, min, max)"
   write(lu,*)"true 0.4 0.98"
   write(lu,*)"# Velocity norm (active, min, max)"
   write(lu,*)"false 0.0 1.0E30"
   write(lu,*)"# Vx component limit (active, min, max)"
   write(lu,*)"false -1.0E30 1.0E30"
   write(lu,*)"# Vy component limit (active, min, max)"
   write(lu,*)"false -1.0E30 1.0E30"
   write(lu,*)"# Median test (active, epsilon, r0min, n_neighbor, dist_max)"
   write(lu,*)"true 0.2 2.0 8 10.0"
   write(lu,*)"# Correlation peak width (active, rcut, rh0max)"
   write(lu,*)"true 0.8 0.5"
   write(lu,*)"# Velocity temporal distribution (active, nstdvel)"
   write(lu,*)"true 3"
   write(lu,*)"# Streamwise velocity dispersion (active, COVmax)"
   write(lu,*)"false 0.4"
   write(lu,*)"# Angular dispersion (active, circvarmax)"
   write(lu,*)"true 0.25"
   write(lu,*)"# Aggregation at point (0:median / 1:mean)"
   write(lu,*)"0"
   close (lu)
end subroutine gen_filter_dat


subroutine gen_PIV_param(workdir)
! generate PIV_param.dat
   use iso_fortran_env, only: error_unit, output_unit
   use errors, only: ERR_IMAGE0001_NOT_PMG, ERR_FLOW_DIRECTION_NOT_DEFINED
   use lspiv_parameter, only: dp, outputs_dir, img_transf, PIV_param, flow_area
   use global_solver_appli, only: report_file, user_velocity, fps, resolution
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   ! -- local variables --
   integer :: lu, nb, imax, imin, jmin, jmax, area_width, flow_direction, velocity_class, v_pixel
   real(kind=dp) :: estimated_velocity
   character(len=2) :: P2
   integer :: Bi, S1, S2, S3, S4, ix, jy, n, ni, nj
   real(kind=dp) :: Dt
   real(kind=dp), parameter :: dir_x = 1.5_dp , dir_y = 0.3_dp
   real(kind=dp) :: alpha

   write(output_unit,'(a)') '---> Generating PIV_param.dat'
   write(report_file,'(a)') '---> Generating PIV_param.dat'

   !read estimated flow data
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//user_velocity,form='formatted',status='old')
   read(lu,*)
   read(lu,*) flow_direction
   read(lu,*)
   read(lu,*) velocity_class
   close (lu)
   select case (velocity_class)
      case (0)  ;  estimated_velocity = 0.3_dp
      case (1)  ;  estimated_velocity = 1.5_dp
      case (2)  ;  estimated_velocity = 3.0_dp
      case (3)  ;  estimated_velocity = 6.0_dp
      case default  ;  estimated_velocity = 1.5_dp
   end select
   !open and read flow area file
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//flow_area,status='old')
   imin = 9999999  ;  jmin = 9999999  ;  imax = 0  ;  jmax = 0
   read(lu,*) nb
   do n = 1, Nb
      read(lu,*) ix, jy
      imin = min(imin,ix)  ;  imax = max(imax,ix)
      jmin = min(jmin,jy)  ;  jmax = max(jmax,jy)
   enddo
   close (lu)
   area_width = min(imax-imin,jmax-jmin)

   !Values
   write(output_unit,*) '    flow area width = ',area_width
   write(report_file,*) '    flow area width = ',area_width
   Bi = min(32,area_width/20)
   if (mod(Bi,2) > 0) Bi = Bi+1 !one forces Bi to be even
   Dt = 1._dp / fps
   !read the first transformed image to get its size ni (width), nj (height)
   open(newunit=lu,file=trim(workdir)//'/'//img_transf//'/'//'image0001_transf.pgm',form='formatted',status='old')
   read(lu,'(a2)') P2
   if (P2 /= 'P2') then
      write(error_unit,'(a)') '>>>> ERROR: image0001_transf.pgm is not a PGM P2'
      write(report_file,'(a)') '>>>> ERROR: image0001_transf.pgm is not a PGM P2'
      stop ERR_IMAGE0001_NOT_PMG
   endif
   read(lu,*) ni, nj
   close (lu)
   !SA size: S1, S2, S3, S4 (South, North, West, East)
   v_pixel = int(abs(estimated_velocity) * Dt / resolution)
   !alpha = sqrt((dir_x*dir_x + dir_y*dir_y)/2._dp)  ! NOTE: proposition JLC du 13/01/2021
   alpha = (dir_x + dir_y)/sqrt(2._dp)  ! NOTE: proposition JLC du 16/01/2021
   select case (flow_direction)
      !No privilegied direction
      case (0) ; S1 = max(2,int(v_pixel * dir_x))  ;  S2 = S1  ;  S3 = S1  ;  S4 = S1
      !South (bottom)
      case (1) ; S1 = max(2,int(v_pixel * dir_x))  ;  S2 = 0  ;  S3 = max(2,int(v_pixel * dir_y))  ;  S4 = S3
      !North (top)
      case (2) ; S1 = 0  ;  S2 = max(2,int(v_pixel * dir_x))  ;  S3 = max(2,int(v_pixel * dir_y))  ;  S4 = S3
      !West (left)
      case (3) ; S1 = max(2,int(v_pixel * dir_y))  ;  S2 = S1  ;  S3 = max(2,int(v_pixel * dir_x))  ;  S4 = 0
      !East (right)
      case (4) ; S1 = max(2,int(v_pixel * dir_y))  ;  S2 = S1  ;  S3 = 0  ;  S4 = max(2,int(v_pixel * dir_x))
      !N-E
      case (5) ; S1 = 0  ;  S2 = max(2,int(v_pixel * alpha))  ;  S3 = 0  ;  S4 = S2
      !S-E
      case (6) ; S1 = max(2,int(v_pixel * alpha))  ;  S2 = 0  ;  S3 = 0  ;  S4 = S1
      !S-W
      case (7) ; S1 = max(2,int(v_pixel * alpha))  ;  S2 = 0  ;  S3 = S1  ;  S4 = 0
      !N-W
      case (8) ; S1 = 0  ;  S2 = max(2,int(v_pixel * alpha))  ;  S3 = S2  ;  S4 = 0
      case default
         write(output_unit,'(a)') '>>>> ERROR: flow direction not defined'
         write(report_file,'(a)') '>>>> ERROR: flow direction not defined'
         write(error_unit,'(a)') '>>>> ERROR: flow direction not defined'
         stop ERR_FLOW_DIRECTION_NOT_DEFINED
   end select

   !writing PIV_param data file
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//PIV_param,form='formatted',status='new')
   write(lu,'(a)') '# FileVersion 2.0 / IA Size'
   write(lu,'(i0)') Bi
   write(lu,'(a)') 'SA size: S1, S2, S3, S4 (bottom, top, left, right)'
   write(lu,'(i0)') S1
   write(lu,'(i0)') S2
   write(lu,'(i0)') S3
   write(lu,'(i0)') S4
   write(lu,'(a)') 'Time interval'
   write(lu,'(f8.6)') Dt
   write(lu,'(a)') 'Taille des images transformees : largeur - hauteur'
   write(lu,'(i0)') ni
   write(lu,'(i0)') nj
   !others data useful later
   write(lu,'(a)') 'Surface coefficient'
   write(lu,'(a)') '0.85'
   write(lu,'(a)') 'Rayon de recherche des vitesses autour du point bathy : rxmax - rymax'
   write(lu,'(a)') '-1.0 -1.0'
   write(lu,'(a)') 'Pas d espace d interpolation de la bathymetrie : Dxp'
   write(lu,'(a)') '0.5 0'
   write(lu,'(a)') 'IA j position'
   write(lu,'(a)') '-1'
   write(lu,'(a)') 'IA i position'
   write(lu,'(a)') '-1'

   close (lu)
end subroutine gen_PIV_param


subroutine PIV(workdir,ncore)
! routine de traitement PIV par lot
! la parallélisation concerne la boucle sur les paires d'images.
! la PIV proprement dite est trop courte pour que la parallélisation apporte vraiment quelque chose.
   use iso_fortran_env, only: output_unit
   use omp_lib, only: omp_get_thread_num
   use lspiv_parameter, only: dp, grid, img_transf, outputs_dir, list_avg, PIV_param, vel_raw, lire_PIV_param, lire_Grid
   use global_solver_appli, only: report_file, nb_images
   use mod_PIV, only: sub_PIV
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   integer, intent(in) :: ncore
   ! -- PIV parameters
   integer :: Bi, Bj  ! IA size
   integer :: Sim, Sjm, Sip, Sjp   ! SA size
   real(kind=dp) :: R_min, R_max
   integer :: ni, nj
   ! -- Grid data
   integer :: compt
   integer, allocatable :: x(:), y(:)
   ! -- local variables --
   integer :: n, p_compteur, lww
   character(len=21) :: image1, image2, piv_dat
   character (len=:), allocatable :: out_file, img1, img2
   character(len=120) :: p_message

   write(output_unit,'(/,a,i0,a)') '---> Compute PIV on image pairs with ',ncore,' cores'
   write(report_file,'(/,a,i0,a)') '---> Compute PIV on image pairs with ',ncore,' cores'

   !---read PIV_param and Grid data
   call lire_PIV_param(trim(workdir)//'/'//outputs_dir//'/'//PIV_param, Bi, Bj, Sim, Sjm, Sip, Sjp, R_min, R_max, ni, nj, .true.)
   call lire_Grid(trim(workdir)//'/'//outputs_dir//'/'//grid,compt,x,y)

   !---images processing
   p_compteur = 0

   !loop over all image files named image????_transf.pgm in the directory
!$omp parallel default(private) &
   !$omp shared(workdir,nb_images,report_file,Bi,Bj,Sim,Sjm,Sip,Sjp,R_min,R_max,ni,nj,compt,x,y,p_compteur) &
   !$omp num_threads(ncore)
!$omp do
   do n = 1, nb_images-1
      write(image1,'(a5,i4.4,a11)') 'image',n,'_transf.pgm'
      write(image2,'(a5,i4.4,a11)') 'image',n+1,'_transf.pgm'
      write(piv_dat,'(a3,i4.4,a4)')'piv',n,'.dat'
#ifdef openmp
      write(report_file,'(5a,i0)') '------> Processing pair ',image1,' and  ',image2,' with core ',omp_get_thread_num()
#endif /* openmp */
#ifndef openmp
      write(report_file,'(4a)') '------> Processing pair ',image1,' and  ',image2
#endif /* openmp */
      allocate (character(len=32+len_trim(workdir)) :: img1, img2, out_file)
      img1 = trim(workdir)//'/'//img_transf//'/'//trim(image1)
      img2 = trim(workdir)//'/'//img_transf//'/'//trim(image2)
      out_file = trim(workdir)//'/'//vel_raw//'/'//trim(piv_dat)
      call sub_PIV(img1,img2,out_file,Bi,Bj,Sim,Sjm,Sip,Sjp,R_min,R_max,ni,nj,compt,x,y,1)
      deallocate(img1,img2,out_file)
      p_compteur = p_compteur + 1
      write(output_unit,'(2(a,i0))') '------> PIV : ',p_compteur,' pairs processed from ',nb_images-1
      write(p_message,'(a,f0.1,a)') 'Step 4 -- PIV : ',real(p_compteur)/real(nb_images-1)*100.,'%'
      call write_progression(workdir,p_message)
   enddo
!$omp end do
!$omp end parallel
   write(output_unit,'(a)') '---> Creating list of avg files'
   write(report_file,'(a)') '---> Creating list of avg files'
   open(newunit=lww,file=trim(workdir)//'/'//outputs_dir//'/'//list_avg,form='formatted',status='unknown')
   do n = 1, p_compteur
      write(piv_dat,'(a3,i4.4,a4)')'piv',n,'.dat'
      write(lww,'(a)') trim(piv_dat)
   enddo
   close(lww)
end subroutine PIV


function mean_velocity(workdir)
!compute the magnitude of the mean vector of average_vel.out
   use iso_fortran_env, only: error_unit
   use errors, only: ERR_FLOW_DIRECTION_NOT_DEFINED
   use lspiv_parameter, only: dp, outputs_dir, average_vel
   implicit none
   ! -- prototype --
   character(len=*), intent(in) :: workdir
   real(kind=dp) :: mean_velocity
   ! -- local variables --
   integer :: lu, ios, n
   real(kind=dp) :: x, y, u, v, mean_u, mean_v

   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//average_vel, form='formatted',status='old')
   mean_u = 0._dp
   mean_v = 0._dp
   n = 0
   do
      read(lu,*,iostat=ios) x, y, u, v
      if (is_iostat_end(ios)) exit
      if (ios /= 0) then
         write(error_unit,'(a)') 'Erreur de lecture du fichier '//trim(workdir)//'/'//outputs_dir//'/'//average_vel
         stop ERR_FLOW_DIRECTION_NOT_DEFINED
      elseif (sqrt(u*u + v*v) > 0.0001_dp) then
         mean_u = mean_u + u
         mean_v = mean_v + v
         n = n + 1
      else
         cycle
      endif
   enddo
   if (n > 0) then
      mean_u = mean_u / real(n,kind=dp)
      mean_v = mean_v / real(n,kind=dp)
   else
      mean_u = 0._dp
      mean_v = 0._dp
   endif
   mean_velocity = sqrt(mean_u*mean_u + mean_v*mean_v)
   close(lu)
end function mean_velocity


subroutine minmax_velocity(workdir,vmin,vmax)
!compute the minimum and the maximum magnitude of the mean vector of average_vel.out
   use iso_fortran_env, only: error_unit
   use errors, only: ERR_READING_FILE
   use lspiv_parameter, only: dp, outputs_dir, average_vel
   implicit none
   ! -- prototype --
   character(len=*), intent(in) :: workdir
   real(kind=dp), intent(out) :: vmin, vmax
   ! -- local variables --
   integer :: lu, ios, n
   real(kind=dp) :: x, y, u, v, u2v2

   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//average_vel, form='formatted',status='old')
   vmin = 1.E30_dp
   vmax = 0._dp
   n = 0
   do
      read(lu,*,iostat=ios) x, y, u, v
      if (is_iostat_end(ios)) exit
      if (ios /= 0) then
         write(error_unit,'(a)') 'Erreur de lecture du fichier '//trim(workdir)//'/'//outputs_dir//'/'//average_vel
         stop ERR_READING_FILE
      else
         u2v2 = sqrt(u*u + v*v)
         if (u2v2 > 0.0001_dp) then
            vmin = min(vmin,u2v2)
            vmax = max(vmax,u2v2)
            n = n+1
         else
            cycle
         endif
      endif
   enddo
   close(lu)
   if (n == 0) then
      !all points have been filtered, so the velocity field is zero
      vmin = 0._dp
      vmax = 0._dp
   endif
end subroutine minmax_velocity


subroutine gen_image_result(workdir, Q_user)
!merge ./img_transf/image0001.pgm and the mean velocity field from ./outputs.dir/average_vel.out

! TODO: ajouter video_creation_time

   use iso_fortran_env, only: error_unit, output_unit
   use errors, only: ERR_EMPTY_FILE, ERR_READING_FILE
   use lspiv_parameter, only: dp, outputs_dir, PIV_param, average_vel, img_transf, read_img_ref, lire_piv_param
   use global_solver_appli, only: report_file, logo_flowpic, final_results, keepAllFiles, &
                                  mean_vel, mean_vel_0, mean_vel_1, pwd, simulation_date, version_flowpic, &
                                  version_number, video_creation_time, exedir, surface_coeff
   use lspiv_parameter, only: gen_white_PNG, run_external_program, f0p
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   real(kind=dp), intent(in), optional :: Q_user
   ! -- interfaces --
   interface
      function mean_velocity(workdir)
         use lspiv_parameter, only: dp
         character(len=*), intent(in) :: workdir
         real(kind=dp) :: mean_velocity
      end function mean_velocity
   end interface
   ! -- local variables --
   character (len=:), allocatable :: command
   character (len=14) :: script = 'script.gnu'
   integer :: lw, lu, n
   ! -- img_ref data
   real(kind=dp) :: xmin, ymin, xmax, ymax, r, x, y, z
   ! -- PIV parameters
   integer :: Bi, Bj  ! IA size
   integer :: Sim, Sjm, Sip, Sjp   ! SA size
   real(kind=dp) :: R_min, R_max
   integer :: ni, nj, ni_reel
   ! -- others variables
   real(kind=dp) :: u, v, vitesse_moyenne, x0, x1, y0, y1, vmin, vmax, echelle
   integer :: ios, m, istop, width, height
   logical :: bExist

   write(output_unit,'(a)') '---> Generating the resulting final image'
   write(report_file,'(a)') '---> Generating the resulting final image'
   call write_progression(workdir,'Step 5 -- Finalization : building velocity field image')

   call read_img_ref(trim(workdir)//'/'//outputs_dir,xmin, ymin, xmax, ymax, r, width, height)
   call lire_PIV_param(trim(workdir)//'/'//outputs_dir//'/'//PIV_param, Bi, Bj, Sim, Sjm, Sip,&
  &Sjp, R_min, R_max, height, width, .true.)
   nj = height  ;  ni = width  !size of rectified images

   vitesse_moyenne = mean_velocity(workdir)
   call minmax_velocity(workdir,vmin,vmax)
   write(report_file,'(5x,a)') 'Velocity:'
   write(report_file,'(10x,3a)') 'Mean magnitude: ',trim(f0p(vitesse_moyenne,3)),' m/s'
   write(report_file,'(10x,3a)') 'Minimum of magnitude: ',trim(f0p(vmin,3)),' m/s'
   write(report_file,'(10x,3a)') 'Maximum of magnitude: ',trim(f0p(vmax,3)),' m/s'
   if (present(Q_user)) then
      write(report_file,'(10x,3a)') 'Discharge: ',trim(f0p(Q_user,3)),' m3/s'
   endif

   !removing half of the vectors to have a more clear view
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//average_vel, form='formatted',status='old')
   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//'mean_velocity',form='formatted',status='unknown')
   !compute scale factor to produce arrows not too large
   echelle = 0._dp
   read(lu,*,iostat=ios) x0, y0, u, v
   if (is_iostat_end(ios)) then
      write(error_unit,'(a)') 'ERREUR : le fichier '//trim(workdir)//'/'//outputs_dir//'/'//average_vel//' est vide'
      stop ERR_EMPTY_FILE
   elseif (ios /= 0) then
      write(error_unit,'(a)') 'Erreur de lecture du fichier '//trim(workdir)//'/'//outputs_dir//'/'//average_vel
      stop ERR_READING_FILE
   endif
   do
      read(lu,*,iostat=ios) x, y, u, v
      if (is_iostat_end(ios)) then
         exit
      elseif (ios /= 0) then
         write(error_unit,'(a)') 'Erreur de lecture du fichier '//trim(workdir)//'/'//outputs_dir//'/'//average_vel
         stop ERR_READING_FILE
      endif
      echelle = max(x-x0,y0-y,echelle)
      x0 = x ; y0 = y
   enddo
   if (vmax > 0.01_dp) then
      echelle = 2._dp * echelle / vmax
   else
      echelle = 1._dp
   endif
   rewind(lu)
   m = 1 ; n = m
   x0 = -1.e30_dp
   do
      read(lu,*,iostat=ios) x, y, u, v
      if (is_iostat_end(ios)) then
         exit
      elseif (ios /= 0) then
         write(error_unit,'(a)') 'Erreur de lecture du fichier '//trim(workdir)//'/'//outputs_dir//'/'//average_vel
         stop ERR_READING_FILE
      endif
      if (x < x0) then !new row
         m = -m ; n = m
      endif
      x0 = x
      if (n > 0) then
         write(lw,'(4(f8.4,1x))') x, y, u*echelle, v*echelle
      endif
      n = -n
   enddo
   close(lu) ; close(lw)

   inquire(file=trim(workdir)//'/'//outputs_dir//'/transect',exist=bExist)

   !generating gnuplot script
   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//script,form='formatted',status='new')
   write(lw,'(a)') 'reset'
   write(lw,'(a,i0,a1,i0)') 'set term png size ',ni,',',nj
   write(lw,'(3a)') 'set output ''',mean_vel_0,''''
   write(lw,'(a)') 'set multiplot'
   write(lw,'(a)') 'unset tics'
   write(lw,'(a)') 'unset border'
   write(lw,'(a)') 'set lmargin 0'
   write(lw,'(a)') 'set rmargin 0'
   write(lw,'(a)') 'set bmargin 0'
   write(lw,'(a)') 'set tmargin 0'
   !As the background picture's size is ni x nj (width x height), we choose xrange and yrange of these values
   write(lw,'(a,i0,a1)') 'set xrange [0:',ni-1,']'
   write(lw,'(a,i0,a)') 'set yrange [',nj-1,':0]'
   !Plot the background image
   write(lw,'(a)') 'plot ''image.png'' binary filetype=png with rgbimage'
   write(lw,'(a)') 'set style arrow 1 head filled size screen 0.025,25,45 lw 2 lc rgb ''green'''
   !The x and y range of the velocity field
   write(lw,'(a,f0.2,a1,f0.2,a1)') 'set xrange [',xmin,':',xmax,']'
   write(lw,'(a,f0.2,a1,f0.2,a1)') 'set yrange [',ymin,':',ymax,']'
   !plot the mean velocity field
   write(lw,'(a)') 'unset clip one' !do not plot the vectors that come out of the graph
   write(lw,'(a)') 'plot ''mean_velocity'' with vectors arrowstyle 1 notitle'
   if (bExist) then
      write(lw,'(a)') 'set clip one'
      write(lw,'(a)') 'set key font ''Carlito:Bold,14'' tc rgb ''red'''
      write(lw,'(a)') 'plot ''transect'' with linespoints lw 4 lc rgb ''red'' title ''Transect'''
   endif
   write(lw,'(a)') 'unset multiplot'

   ni_reel = ni
   ni = max(600,ni)+80  !add 80 pixels for left and right margins
   if (ni_reel < 600) then
      !We need to generate a white image (600+80) x nj as background to be sure that resulting image is wide enough
      call gen_white_PNG(nj,ni,trim(workdir)//'/'//outputs_dir//'/white.png')
   endif
   nj = nj+240 !we add 240 pixels for bottom and top margins
   !Now we put the raw output image in the output image
   write(lw,'(a)') 'reset'
   write(lw,'(a,i0,a1,i0,a)') 'set term png size ',ni,',',nj,' nocrop'
   write(lw,'(3a)') 'set output ''',mean_vel_1,''''
   write(lw,'(a)') 'unset tics'
   write(lw,'(a)') 'unset border'
   write(lw,'(a,i0,a1)') 'set lmargin at screen 40./',ni,'.'
   write(lw,'(a,i0,a2)') 'set rmargin at screen 1.-(40./',ni,'.)'
   write(lw,'(a,i0,a1)') 'set bmargin at screen 70./',nj,'.'
   write(lw,'(a,i0,a2)') 'set tmargin at screen 1.-(170./',nj,'.)'
   !plot the title and the subtitles
   write(lw,'(a)') 'set title ''{/Carlito:Bold=24 Surface velocity field}'' offset 0,6.0 '
   write(lw,'(3a)') 'set label 1 ''{/Carlito=20 Average of surface velocities = ', trim(f0p(vitesse_moyenne,2)), &
                    ' m/s}'' center at graph 0.5,1 offset character 0,4.5'

   write(lw,'(5a)') 'set label 2 ''{/Carlito=20 Min = ',trim(f0p(vmin,2)),' m/s  -  Max = ',trim(f0p(vmax,2)), &
                    ' m/s}'' center at graph 0.5,1 offset character 0,3.0'
   if (present(Q_user)) then
      if (Q_user > 0.999_dp) then
         write(lw,'(3a,a,a)') 'set label 7 ''{/Carlito=20 Discharge = ',trim(f0p(Q_user,3)), &
                          ' m^3/s }{/Carlito=12 (Coeff = ',trim(surface_coeff),&
                          ')}'' center at graph 0.5,1 offset character 0,1 tc rgb ''blue'''
      else

         write(lw,'(a,i3,a,a,a)') 'set label 7 ''{/Carlito=20 Discharge = ',nint(Q_user*1000._dp), &
                          ' L/s }{/Carlito=12 (Coeff = ',trim(surface_coeff),&
                          ')}'' center at graph 0.5,1 offset character 0,1 tc rgb ''blue'''
      endif
   else
      write(lw,'(a,a)') 'set label 7 ''{/Carlito=20 Discharge not computed', &
                          '}'' center at graph 0.5,1 offset character 0,1 tc rgb ''blue'''
   endif
   !rounding vitesse_moyenne
   x = -1._dp ; y = 0.25_dp ; z = 0.1_dp
   do
      if (vitesse_moyenne >= x .and. vitesse_moyenne < y) then
         vitesse_moyenne = z
         exit
      else
         x = y ; y = y + 0.5_dp ; z = (x+y)/2._dp
      endif
   enddo
   !plot the legend
   write(lw,'(a)') 'set style arrow 1 head filled size screen 0.025,25,45 lw 2 lc rgb ''green'''
   x0 = 0.01 ; y0 = 30._dp/nj
   write(lw,'(a,2(f5.2,a))') 'set label 6 ''{/Carlito=12 Video date: '//video_creation_time//'}'' at screen ',  &
                             x0,',',y0,' left tc rgb ''gray'' front'

   x0 = 0.90_dp ; y0 = 30._dp/nj
   write(lw,'(3a,2(f6.3,a))') 'set label 3 ''{/Carlito=18 Scale ',trim(f0p(vitesse_moyenne,1)),' m/s : }'' at screen ', &
                              x0,',',y0,' right tc rgb ''black'' front'
   x0 = x0+0.01_dp ; y0 = 30._dp/nj ; x1 = x0 + echelle*vitesse_moyenne*ni_reel/(xmax-xmin)/ni ; y1 = y0
   write(lw,'(4(a,f6.3),a)') 'set arrow 1 from screen ',x0,',',y0,' to screen ',x1,',',y1,' arrowstyle 1'
   x0 = 0.95 ; y0 = 0.01
   write(lw,'(5a,2(f5.2,a))') 'set label 4 ''{/Carlito=12 FlowPic ',version_flowpic,' and solver ', &
                              trim(version_number),'}'' at screen ', x0,',',y0,' right tc rgb ''gray'' front'
   x0 = 0.01 ; y0 = 0.01
   write(lw,'(a,2(f5.2,a))') 'set label 5 ''{/Carlito=12 Computation date: '//simulation_date//'}'' at screen ', x0,',',y0, &
                             ' left tc rgb ''gray'' front'
   if (ni_reel < 600) then
      !plot the white background first, then the image centered
      write(lw,'(3a)')      'plot ''white.png'' binary filetype=png with rgbimage, \'
      write(lw,'(3a,i0,a)') '     ''',mean_vel_0,''' binary filetype=png origin=(',(ni-ni_reel)/2, &
                            ',0) dx=1. dy=1. with rgbimage notitle'
   else
      !plot the image
      write(lw,'(3a)') 'plot ''',mean_vel_0,''' binary filetype=png with rgbimage notitle'
   endif

   !Add the FlowPic logo
   write(lw,'(a)') 'reset'
   write(lw,'(a,i0,a1,i0,a)') 'set term png size ',ni,',',nj,' nocrop'
   write(lw,'(3a)') 'set output ''',mean_vel,''''
   write(lw,'(a)') 'unset tics'
   write(lw,'(a)') 'unset border'
   write(lw,'(a)') 'set lmargin 0'
   write(lw,'(a)') 'set rmargin 0'
   write(lw,'(a)') 'set bmargin 0'
   write(lw,'(a)') 'set tmargin 0'
   write(lw,'(3a)')        'plot ''',mean_vel_1,''' binary filetype=png with rgbimage, \'
   write(lw,'(3a,i0,a)')   '     ''',trim(exedir)//'/'//logo_flowpic,''' binary filetype=png origin=(20,', &
                              nj-50-5,') dx=0.25 dy=0.25 with rgbimage notitle'

   flush(lw)
   close(lw)

   allocate(character(len=2*len_trim(workdir)+len_trim(img_transf)+len_trim(final_results)+len_trim(outputs_dir)+43) :: command)
   ! conversion image0001_transf.pgm into image.png
   write(command,'(2a,1x,a)') 'convert ',trim(workdir)//'/'//img_transf//'/'//'image0001_transf.pgm', &
                                   trim(workdir)//'/'//outputs_dir//'/'//'image.png'
   istop = 0 ; call run_external_program(command,.true.,istop)
   ! run gnuplot script
   write(command,'(4a)') 'cd ',trim(workdir)//'/'//outputs_dir,' && gnuplot ',script
   istop = 0 ; call run_external_program(command,.true.,istop)

   ! remove temporary files
   if (.not. keepAllFiles) then
      open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//'image.png',status='old')
      close(lw,status='delete')
      if (ni_reel < 600) then
         open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//'white.png',status='old')
         close(lw,status='delete')
      endif
      open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//mean_vel_0,status='old')
      close(lw,status='delete')
      open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//mean_vel_1,status='old')
      close(lw,status='delete')
      open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//script,status='old')
      close(lw,status='delete')
      open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//'GRP_ortho.dat',status='old')
      close(lw,status='delete')
      open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//'mean_velocity',status='old')
      close(lw,status='delete')
   endif
end subroutine gen_image_result


subroutine check_user_email(workdir,user_email)
!check if there is a problem with user_email.dat
   use iso_fortran_env, only: error_unit
   use lspiv_parameter, only: is_valid_email
   implicit none
   ! -- prototype --
   character(len=*), intent(in) :: workdir
   character(len=:), allocatable, intent(out) :: user_email
   ! -- local variables
   integer :: fSize, lw
   logical :: bFail

   inquire(file=trim(workdir)//'/'//'user_email.dat',size=fSize)
   if (fSize > 0) then
      allocate (character(len=fSize) :: user_email)
      open(newunit=lw,file=trim(workdir)//'/'//'user_email.dat',form='formatted',status='old')
      read(lw,'(a)') user_email
      close (lw)
      if (.not.is_valid_email(user_email)) then
         write(error_unit,'(3a)') '>>>> ERROR the email address ',trim(user_email),' is not valid.'
         bFail = .true.
      else
         bFail = .false.
      endif
   else
      write(error_unit,'(a)') '>>>> ERROR: the file user_email.dat does not exist or is empty'
      bFail = .true.
   endif
   if (bFail) then
      if (allocated(user_email)) deallocate (user_email)
      allocate (character(len=27) :: user_email)
      user_email = 'prj.flowpic.dev@lists.irstea.fr'
      write(error_unit,'(12x,2a)') 'alternate user email used : ',trim(user_email)
   endif
end subroutine check_user_email


subroutine remove_dir_structure(workdir)
!remove all not needed subdirs in the working directory
   use iso_fortran_env, only: output_unit
   use global_solver_appli, only: report_file
   use lspiv_parameter, only: img_pgm,img_stab,img_transf,transects, vel_real,vel_scal,vel_raw,vel_filter, run_external_program
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   ! -- local variables --
   character(len=:),allocatable :: command
   integer :: istop

   write(output_unit,'(/,2a)') '---> Removing folder structure in ',trim(workdir)
   write(report_file,'(/,2a)') '---> Removing folder structure in ',trim(workdir)

   allocate(character(len=len_trim(workdir)+113) :: command)
   write(command,'(a3,a,a10,8(1x,a))') 'cd ',trim(workdir),' && rm -R ',img_pgm,img_stab,img_transf,transects, &
                                                                         vel_real,vel_scal,vel_raw,vel_filter
   call run_external_program(command,.true.,istop)
end subroutine remove_dir_structure

function mail_body(language, simulation_date, vitesse_moyenne, Q_user)

    use lspiv_parameter, only: f0p, dp

    implicit none

    character(len = 1100) :: mail_body
    character(len=2), intent(in) :: language
    character(len = *), intent(in) :: simulation_date
    real(kind=dp), intent(in) :: vitesse_moyenne
    real(kind=dp), intent(in), optional :: Q_user
    character(len=50) :: ligne_debit

    if (language == 'EN')then

        if (present(Q_user)) then
            if (Q_user > 0.999_dp) then
                write(ligne_debit,'(3a)')'Discharge estimation is ',trim(f0p(Q_user,3)), ' m^3/s'
            else
                write(ligne_debit,'(a,i3,a)')'Discharge estimation is ',nint(Q_user*1000._dp), ' L/s'
            endif
        else
        write(ligne_debit,'(a)')'Discharge has not been computed.'
        endif

        write(mail_body,'(3a,f5.2,a)')"Hello,"//NEW_LINE("a")//&
        &NEW_LINE("a")//&
        &"Please, find enclosed the results of your FlowPic measurement on ",trim(simulation_date),"."//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"The file solver_report.log is a log of all the computations done on the server, it&
        & contains intermediate results that may be useful."//NEW_LINE("a")//&
        &"Here you will find any error messages that the solver may have generated at various steps &
        &of the calculation."//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"Image mean_vel.png shows the mean surface velocity field computed by the solver from your data."//NEW_LINE("a")//&
        &"The mean surface velocity is ",vitesse_moyenne," m/s."//NEW_LINE("a")//&
        &trim(ligne_debit)//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"Archive etude.lspiv.zip gathers the necessary files, excluding video, to import in Fudaa-LSPIV."//NEW_LINE("a")//&
        &"You can find a presentation of Fudaa-LSPIV here:"//NEW_LINE("a")//&
        &"https://riverhydraulics.inrae.fr/en/tools/measurement-software/fudaa-lspiv-2/"//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"Disclaimer: The User assumes full responsibility for the use he makes of the information &
        &obtained with FlowPic."//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"Enjoy FlowPic!"//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"The FlowPic team"//NEW_LINE("a")

    else
        if (present(Q_user)) then
            if (Q_user > 0.999_dp) then
                write(ligne_debit,'(3a)')'Le débit est estimé à ',trim(f0p(Q_user,3)), ' m^3/s'
            else
                write(ligne_debit,'(a,i3,a)')'Le débit est estimé à ',nint(Q_user*1000._dp), ' L/s'
            endif
        else
            write(ligne_debit,'(a)')"Le débit n'a pas été calculé."
        endif

        write(mail_body,'(3a,f5.2,a)')"Bonjour,"//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"Veuillez trouver ci-joint les résultats de votre mesure FlowPic du ",trim(simulation_date),"."//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"Le fichier solver_report.log est une trace de tous les calculs faits sur le serveur, il contient des "//&
        &"résultats intermédiaires qui peuvent être utiles."//NEW_LINE("a")//&
        &"Vous y trouverez les éventuels messages d'erreur que le solveur a pu générer aux différentes étapes "//&
        &"du calcul."//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"L'image mean_vel.png montre le champ de vitesse de surface moyen calculé par le solveur à partir de "//&
        &"vos données."//NEW_LINE("a")//&
        &"La vitesse de surface moyenne est ",vitesse_moyenne," m/s."//NEW_LINE("a")//&
        &trim(ligne_debit)//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"L'archive etude.lspiv.zip regroupe les fichiers nécessaires, hors vidéo, pour un import dans "//&
        &"Fudaa-LSPIV dont vous pouvez trouver une présentation ici :"//NEW_LINE("a")//&
        &"https://riverhydraulics.inrae.fr/outils/logiciels/fudaa-lspiv/"//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"Clause de non-responsabilité : L'Utilisateur assume l'entière responsabilité de l'utilisation "//&
        &"qu'il fait des informations obtenues avec FlowPic."//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"Bon FlowPicorage!"//NEW_LINE("a")//&
        &""//NEW_LINE("a")//&
        &"L'équipe FlowPic"//NEW_LINE("a")
    endif
    return
end function mail_body

subroutine finalize_results(workdir,user_email,istop,Q_user)
!generate a file archive containing the results and email it to the user
   use iso_fortran_env, only: error_unit, output_unit
   use errors, only: ERR_USER_EMAIL_ADRESS_NOT_VALID
   use lspiv_parameter, only: dp, outputs_dir
   use global_solver_appli, only: report_file, keepAllFiles, final_results, pwd, mean_vel, simulation_date, exedir
   use lspiv_parameter, only: is_valid_email, run_external_program, f0p
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   character (len=*), intent(in) :: user_email !email where to send the results file
   integer,intent(out) :: istop
   real(kind=dp), intent(in), optional :: Q_user
   ! -- interfaces --
   interface
      function mean_velocity(workdir)
         use lspiv_parameter, only: dp
         character(len=*), intent(in) :: workdir
         real(kind=dp) :: mean_velocity
      end function mean_velocity
      function mail_body(language, simulation_date, vitesse_moyenne, Q_user)
         use lspiv_parameter, only: dp
         character(len = 1100) :: mail_body
         character(len=2), intent(in) :: language
         character(len = *), intent(in) :: simulation_date
         real(kind=dp), intent(in) :: vitesse_moyenne
         real(kind=dp), intent(in), optional :: Q_user
      end function mail_body
   end interface
   ! -- local variables --
   character (len=:), allocatable :: command
   character(len=45) :: fm
   integer :: values(8), lu, ios, lw, n
   character :: ddate*8, time*10, zone*5
   character(len=:), allocatable :: message_file
   ! NOTE: The Irstea SMTP server does not accept subject field in UTF-8, so do not add an accent to "resultat".
   character(len=40), parameter :: object_FR = '"Les resultats de votre mesure FlowPic"'
   character(len=37), parameter :: object_EN = '"The results of your FlowPic measure"'
   character(len=300) :: ligne
   character(len=2) :: language
   character(len=40) :: object
   real(kind=dp) :: vitesse_moyenne

   call write_progression(workdir,'Step 5 -- Finalization : sending results')

   ! NOTE: mean_velocity() must be called before moving outputs.dir to final_results folder
   vitesse_moyenne = mean_velocity(workdir)

   allocate(character(len=8+2*len_trim(workdir)+len_trim(outputs_dir)+len_trim(final_results)+len_trim(mean_vel)) :: command)
   !moving mean_vel.png out of outputs.dir next to solver_report.log
   write(command,'(a)') 'mv '//trim(workdir)//'/'//outputs_dir//'/'//mean_vel//' '//trim(workdir)//'/'//final_results//'/'
   istop = 0 ; call run_external_program(command,.true.,istop)
   !moving outputs.dir to final_results folder
   write(command,'(a)') 'mv '//trim(workdir)//'/'//outputs_dir//' '//trim(workdir)//'/'//final_results//'/'
   istop = 0 ; call run_external_program(command,.true.,istop)
   !compressing outputs.dir in etude.lspiv.zip
   deallocate(command)
   allocate(character(len=35+len_trim(workdir)+len_trim(outputs_dir)+len_trim(final_results)) :: command)
   write(command,'(a)') 'cd '//trim(workdir)//'/'//final_results//' && '//'zip -r -m etude.lspiv.zip '//outputs_dir//'/'
   istop = 0 ; call run_external_program(command,.true.,istop)

   !removing folder structure, keeping final_results folder
   if (.not.keepAllFiles) call remove_dir_structure(workdir)

   !closing report file and moving it to final_results folder
   call date_and_time(ddate,time,zone,values)
   fm = '(/,a,i2.2,a,i2.2,a,i4,a,i2.2,a,i2.2,a,i2.2,a)'
   write(report_file,fmt=fm) 'End of the report at ',values(3),'/',values(2),'/',values(1),' (',values(5),':', &
                                                     values(6),':',values(7),')'
   close (report_file)
   deallocate(command)
   allocate(character(len=24+2*len_trim(workdir)+len_trim(final_results)) :: command)
   write(command,'(a)') 'mv '//trim(workdir)//'/solver_report.log '//trim(workdir)//'/'//final_results//'/'
   istop = 0 ; call run_external_program(command,.true.,istop)

   !sending the results to the users
   deallocate (command)
   if (is_valid_email(user_email)) then
      if (index(user_email,'.fr') > 0 .or. index(user_email,'.FR') > 0) then
         language = 'FR'
      else
         language = 'EN'
      endif
      !personnalization of the body of the mail message
!       allocate (character(len=len_trim(pwd)+29) :: message_file)
!       select case (language)
!          case ('FR')
!             message_file = trim(pwd)//'/install_solver/mail_body_FR.txt'
!             object = trim(object_FR)
!          case default
!             message_file = trim(pwd)//'/install_solver/mail_body_EN.txt'
!             object = trim(object_EN)
!       end select
!       open(newunit=lu,file=trim(message_file),form='formatted',status='old')
      open(newunit=lw,file=trim(workdir)//'/'//final_results//'/message.txt',form='formatted',status='unknown')
!       do
!          read(lu,'(a)',iostat=ios) ligne
!          if (is_iostat_end(ios)) exit
!          n = index(ligne,'<date_heure>')
!          if (n > 0) then
!             write(ligne(n:),'(a)') trim(simulation_date)
!             write(lw,'(a)') trim(ligne)
!             cycle
!          endif
!          n = index(ligne,'<vitesse_moyenne>')
!          if (n > 0) then
!             write(ligne(n:),'(f5.2,a)') vitesse_moyenne, ' m/s'
!             write(lw,'(a)') trim(ligne)
!             cycle
!          endif
!          n = index(ligne,'<debit>')
!          if (n > 0 ) then
!             if (present(Q_user)) then
!                if (Q_user > 0.999_dp) then
!                   write(ligne(n:),'(2a)') trim(f0p(Q_user,3)), ' m^3/s'
!                else
!                   write(ligne(n:),'(i3,a)') nint(Q_user*1000._dp), ' L/s'
!                endif
!                write(lw,'(a)') trim(ligne)
!             endif
!             cycle
!          endif
!          n = index(ligne,'<no_debit>')
!          if (n > 0 ) then
!             if (.not.present(Q_user)) then
!                write(lw,'(a)') trim(ligne(:n-1))
!             endif
!             cycle
!          endif
!          write(lw,'(a)') trim(ligne)
         if (present(Q_user)) then
             write(lw,*)trim(mail_body(language, trim(simulation_date), vitesse_moyenne, Q_user))
         else
             write(lw,*)trim(mail_body(language, trim(simulation_date), vitesse_moyenne))
         endif
!       enddo
      close(lu) ; close(lw)
!       allocate (character(len=1000) :: command)
!       !NOTE : take care to put trim(user_email) between ""
!       !NOTE: we have to redirect the standard output of the sendemail command because it writes its error messages there
!       write(command,'(*(a))') 'cd '//trim(workdir)//'/'//final_results, &
!                             ' && sendemail -f noreply@edf.fr -t '//'"'//trim(user_email)//'"',' -u '//object, &
!                             ' -o message-file=message.txt'//' -o message-charset=UTF8', &
!                             ' -a etude.lspiv.zip '//mean_vel//' solver_report.log', &
!                             ' -s mailhost.der.edf.fr > tmp.log'
!       write(output_unit,'(a)') '---> Email command:'
!       write(output_unit,'(a)') trim(command)
!       istop = 0 ; call run_external_program(command,.true.,istop)
!       open (newunit=lu,file=trim(workdir)//'/'//final_results//'/tmp.log',status='old',form='formatted')
!       do
!          read(lu,'(a)',iostat=ios) ligne
!          if (is_iostat_end(ios)) exit
!          write(output_unit,'(a)') trim(ligne)
!          if (index(ligne,'ERROR') > 0) write(error_unit,'(a)') trim(ligne)
!       enddo
!       close (lu,status='delete')
!       if (istop == 0) then
!          write(output_unit,'(a)') '---> Final results sent successfully'
!       else
!          write(output_unit,'(a,i0)') '---> The sending of the final results has failed with error code ',istop
!          write(error_unit,'(a,i0)') '---> The sending of the final results has failed with error code ',istop
!       endif
!       flush (error_unit)
!       flush (output_unit)
   else
      write(error_unit,'(3a)') 'ERROR: user email (',trim(user_email),') is not a valid address!'
      istop = ERR_USER_EMAIL_ADRESS_NOT_VALID
   endif

end subroutine finalize_results


subroutine write_progression(workdir,message)
! write message in the progression file
! performs writing only if at least 5 seconds have elapsed since the previous writing.
   implicit none
   ! -- prototype
   character(len=*), intent(in) :: workdir
   character(len=*), intent(in) :: message
   ! -- local variables --
   integer, save :: previous_time
   integer, parameter :: step_wp = 1
   integer :: lwp, current_time, vtime(8)
   logical, save :: first_call = .true.

   call date_and_time(values = vtime)
   current_time = 3600*vtime(5) + 60*vtime(6) + vtime(7)
   if (first_call) then
      first_call = .false.
      previous_time = current_time
      open(newunit=lwp,file=trim(workdir)//'/progression_file.log',status='unknown',form='formatted')
      write(lwp,'(a)') trim(workdir)//' -- '//trim(message)
      flush(lwp)
      close(lwp)
   elseif (current_time > previous_time+step_wp) then
      previous_time = current_time
      open(newunit=lwp,file=trim(workdir)//'/progression_file.log',status='unknown',form='formatted')
      write(lwp,'(a)') trim(workdir)//' -- '//trim(message)
      flush(lwp)
      close(lwp)
   else
      continue
   endif
end subroutine write_progression


function Q_compute(workdir) result(Q)
! compute the discharge through the provided cross section
   use lspiv_parameter, only: dp, outputs_dir, discharge, bathy
   use global_solver_appli, only: report_file, user_transect
   use mod_bathy_compute, only: sub_bathy_compute
   use mod_Q_compute, only: sub_Q_compute
   implicit none
   ! -- prototype
   character(len=*), intent(in) :: workdir
   real(kind=dp) :: Q
   ! -- local variables --
   integer :: lw
   real(kind=dp) :: stage, wetted_area, V_mean
   logical :: bExist

   !if user_transect does not exist we exit
   inquire(file=trim(workdir)//'/'//outputs_dir//'/'//user_transect, exist=bExist)
   if (.not.bExist) then
      Q = -9999._dp
      return
   endif

   call gen_bathy(trim(workdir)//'/'//outputs_dir)

   call sub_bathy_compute(trim(workdir)//'/'//outputs_dir)

   call sub_Q_compute(workdir)

   write(report_file,'(a)') 'Discharge:'
   inquire(file=trim(workdir)//'/'//outputs_dir//'/'//discharge,exist=bExist)
   if (bExist) then
      !results extraction
      open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//discharge,status='old')
      read(lw,'(4f10.3)') stage, Q, wetted_area, V_mean
      !change Q and V_mean to their magnitude
      Q = abs(Q)  ;  V_mean = abs(V_mean)
      close(lw)
      write(report_file,'(a,f10.3)') 'Stage                     = ',stage
      write(report_file,'(a,f10.3)') 'Discharge (magnitude)     = ',Q
      write(report_file,'(a,f10.3)') 'Wetted area               = ',wetted_area
      write(report_file,'(a,f10.3)') 'Mean velocity (magnitude) = ',V_mean
      write(report_file,'(a)') ''
   else
      write(report_file,'(a)') 'Discharge computation failed, no result available'
      write(report_file,'(a)') 'Take care your transect is in the flow area'
      Q = -99999.999_dp
   endif


end function Q_compute


subroutine gen_bathy(workdir)
! generate the bathy.dat file from the section_profile.dat user file
   use iso_fortran_env, only: error_unit, output_unit
   use lspiv_parameter, only: dp, point2D, outputs_dir, bathy, PIV_param, read_coeff_ortho
   use global_solver_appli, only: user_transect, report_file, resolution, grid_step, surface_coeff
   use mod_ortho, only: ortho_rectif
   implicit none
   ! -- prototype
   character(len=*), intent(in) :: workdir
   ! -- local variables --
   integer :: lw, lu, lv, ios, ii, jj, i, nbc
   real(kind=dp) :: hh, xx, yy, zz, a(11), Dxp, xx0, yy0
   character(len=120) :: ligne
   logical :: first_pt
   type(point2D) :: pt_ini(2), pt_ortho
   real(kind=dp) :: pt_para(25,3)
   character :: section_shape

   write(report_file,'(a)') '---> Generating bathy.dat'
   write(output_unit,'(a)') '---> Generating bathy.dat'

   call read_coeff_ortho(trim(workdir),nbc,a)

   open(newunit=lw,file=trim(workdir)//'/'//bathy,form='formatted',status='new')
   open(newunit=lu,file=trim(workdir)//'/'//user_transect,form='formatted',status='old')
   open(newunit=lv,file=trim(workdir)//'/'//'transect',form='formatted',status='new')
   first_pt = .true.
   write(report_file,'(a)') 'cross-section for discharge computation:'
   write(output_unit,'(a)') 'cross-section for discharge computation:'
   write(report_file,'(a)') ' i     j     h       x      y       z'
   write(output_unit,'(a)') ' i     j     h       x      y       z'

   surface_coeff = '0.85'
   do
      read(lu,'(a)',iostat=ios) ligne
      if (ligne(1:1) == '*' .or. len_trim(ligne) == 0) then
         cycle
      else if (ligne(1:1) == 'f' .or. ligne(1:1) == 'F')then
         section_shape = 'f'
         exit
      else if (ligne(1:1) == 'r' .or. ligne(1:1) == 'R')then
         section_shape = 'r'
         exit
      else if (ligne(1:1) == 'p' .or. ligne(1:1) == 'P')then
         section_shape = 'p'
         exit
      endif
   enddo
   do
      read(lu,'(a)',iostat=ios) ligne
      if (ios /= 0) exit
      if (ligne(1:1) == '*' .or. len_trim(ligne) == 0) then
         cycle
      endif
      read(ligne,*) surface_coeff
      exit
   end do

   if (section_shape == 'r' .or. section_shape == 'p')then
      do
         read(lu,'(a)',iostat=ios) ligne
         if (ligne(1:1) == '*' .or. len_trim(ligne) == 0)then
            cycle
         else
            read(ligne,*) hh
            exit
         endif
      end do
      do
         read(lu,'(a)',iostat=ios) ligne
         if (ligne(1:1) == '*' .or. len_trim(ligne) == 0)then
            cycle
         else
            read(ligne,*) ii, jj ! premiere berge
            exit
         endif
      end do
      pt_ini(1)%x = real(ii,kind=dp)
      pt_ini(1)%y = real(jj,kind=dp)
      do
         read(lu,'(a)',iostat=ios) ligne
         if (ligne(1:1) == '*' .or. len_trim(ligne) == 0)then
            cycle
         else
            read(ligne,*) ii, jj ! deuxieme berge
            exit
         endif
      end do
      pt_ini(2)%x = real(ii,kind=dp)
      pt_ini(2)%y = real(jj,kind=dp)
      if (section_shape == 'r') then
         pt_ortho = ortho_rectif(pt_ini(1),a,resolution)
         xx = pt_ortho%x*resolution
         yy = pt_ortho%y*resolution
         zz = -hh
         write(lw,'(3f10.3)') xx, yy, 0.0
         write(lw,'(3f10.3)') xx, yy, zz
         write(report_file,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, 0.0
         write(report_file,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, zz
         write(output_unit,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, 0.0
         write(output_unit,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, zz
         write(lv,'(f0.3,1x,f0.3)') xx, yy
         xx0 = xx  ;  yy0 = yy
         pt_ortho = ortho_rectif(pt_ini(2),a,resolution)
         xx = pt_ortho%x*resolution
         yy = pt_ortho%y*resolution
         write(lw,'(3f10.3)') xx, yy, zz
         write(lw,'(3f10.3)') xx, yy, 0.0
         write(report_file,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, zz
         write(report_file,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, 0.0
         write(output_unit,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, zz
         write(output_unit,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, 0.0
         write(lv,'(f0.3,1x,f0.3)') xx, yy
      else if (section_shape == 'p')then
         call get_parabola(pt_ini, hh, pt_para)
         do i=1,25
            pt_ini(1)%x = pt_para(i,1)
            ii = int(pt_ini(1)%x)
            pt_ini(1)%y = pt_para(i,2)
            jj = int(pt_ini(1)%y)
            pt_ortho = ortho_rectif(pt_ini(1),a,resolution)
            xx = pt_ortho%x*resolution
            yy = pt_ortho%y*resolution
            zz = pt_para(i,3)
            hh = -zz
            write(lw,'(3f10.3)') xx, yy, zz
            write(report_file,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, zz
            write(output_unit,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, zz
            write(lv,'(f0.3,1x,f0.3)') xx, yy
            if (first_pt) then
               xx0 = xx  ;  yy0 = yy
               first_pt = .false.
            endif
         end do
      endif
   else ! section_shape == 'f'
      do
         read(lu,'(a)',iostat=ios) ligne
         if (ios /= 0) exit
         if (ligne(1:1) == '*' .or. len_trim(ligne) == 0) cycle
         read(ligne,*) ii, jj, hh
         pt_ini(1)%x = real(ii,kind=dp)
         pt_ini(1)%y = real(jj,kind=dp)
         pt_ortho = ortho_rectif(pt_ini(1),a,resolution)
         xx = pt_ortho%x*resolution
         yy = pt_ortho%y*resolution
         zz = -hh
         write(lw,'(3f10.3)') xx, yy, zz
         write(report_file,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, zz
         write(output_unit,'(2(i0,3x),4(f0.3,3x))') ii, jj, hh, xx, yy, zz
         write(lv,'(f0.3,1x,f0.3)') xx, yy !save x & y coordinate to draw cross-section on result image
         if (first_pt) then
            xx0 = xx  ;  yy0 = yy
            first_pt = .false.
         endif
      enddo
   endif
   close (lw)
   close (lu)
   close (lv)

   !updating PIV_param.dat with Dxp
   Dxp = sqrt((xx-xx0)**2 + (yy-yy0)**2) / 24._dp
   open(newunit=lu,file=trim(workdir)//'/'//PIV_param,form='formatted',status='old')
   do i = 1, 13
      read(lu,*)
   enddo
   write(lu,*) trim(surface_coeff)
   write(lu,'(a)') 'Rayon de recherche des vitesses autour du point bathy : rxmax - rymax'
   write(lu,'(f0.3,1x,f0.3)') grid_step%x, grid_step%y
   write(lu,'(a)') 'Pas d espace d interpolation de la bathymetrie : Dxp'
   write(lu,'(f0.3,1x,i1)') Dxp, 0
   write(lu,'(a)') 'IA j position'
   write(lu,'(a)') '-1'
   write(lu,'(a)') 'IA i position'
   write(lu,'(a)') '-1'
   close (lu)

   flush(report_file)

end subroutine gen_bathy

subroutine get_parabola(pt_ini, hh, pt_para)
   use lspiv_parameter, only: point2D
   use lspiv_parameter, only: dp
   implicit none
   type(point2D) :: pt_ini(2), pt_ortho
   real(kind=dp) :: hh
   real(kind=dp) :: pt_para(25,3)
   type(point2D) :: interval
   integer :: i
   real(kind=dp) :: a, decalage

   decalage   = (pt_ini(1)%x+pt_ini(2)%x)/2
   interval%x = (pt_ini(2)%x-pt_ini(1)%x)/24
   interval%y = (pt_ini(2)%y-pt_ini(1)%y)/24
   a = hh/((pt_ini(1)%x-decalage)**2)
   do i=0,24
       pt_para(i+1,1)=pt_ini(1)%x+i*interval%x
       pt_para(i+1,2)=pt_ini(1)%y+i*interval%y
       pt_para(i+1,3)=a*(pt_para(i+1,1)-decalage)**2 - hh
   end do
end subroutine get_parabola


