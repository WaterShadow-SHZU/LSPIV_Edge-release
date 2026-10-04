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

module mod_filter

   use lspiv_parameter, only: dp, filters, img_ref, list_avg, PIV_param, vel_filter,&
                            & vel_raw, median

   contains

subroutine sub_filter(dir1, dir2, dt_in)
! Corrections by JLC on June 24, 2014: filter thresholds read in PIV_param.dat file;
!  add screening with correlation thresholds; all conditions now are strict (gt and lt)

! Modification by JLC on Oct 31, 2016:
! Read min/max thresholds on Vx and Vy for Fudaa-LSPIV v1.5

! Modification by JLC on July 30, 2019:
! Exit conditions of DO loops
!
!  dir1 = './outputs.dir' if used by Fudaa-LSPIV
!  dir1 = param1 if station
!  dir2 = './' if used by Fudaa-LSPIV
!  dir2 = param2 if station

   use iso_fortran_env, only: error_unit
   use errors, only: ERR_READ_LIST_AVG, ERR_STREAMWISE_FILTER_NO_TRANSECT
   use kdtree2_module
   implicit none
   ! protype
   character (len=*), intent(in) :: dir1, dir2
   real(kind=dp), intent(in), optional :: dt_in
   ! local variables
   real(kind=dp) :: xmin,ymin,xmax,ymax,resol

   real(kind=dp) :: Dt, smin, smax, vxmin, vxmax, vymin, vymax, epsi, r0min, dist_max, rcut, rhomax, covmax, circvarmax
   integer :: n_neighbor, aggregType, nstdvel
!   Dt            = time interval [s] between two images
!   smin & smax   = velocity magnitude thresholds
!   vxmin & vxmax = Vx velocity component thresholds
!   vymin & vymax = Vy velocity component thresholds
!   epsi          = median test parameter : Fluctuation tolerance [pix]
!   r0min         = median test parameter : Threshold for filtering
!   n_neighbor    = kd-tree query parameters : numbers of neighbors around point
!   dist_max      = kd-tree query parameters : maximum distance to consider point as neighbor
!   rcut          = correlation peak width filter : min corr. level for peak width estimation
!   rhomax        = correlation pic width filter  : tolerance for velocity norm/correlation peak width ratio
!   nstdvel       = temporal dispersion filter : standard deviation factor around mean
!   covmax        = streamwise velocity dispersion filter : threshold on coefficient of variation
!   circvarmax    = angular dispersion filter : threshold on circular variance
!   aggregType    = aggregation at point, 0:median / 1:mean

   logical              :: bCor, bNorm, bVx, bVy, bMedTest, bCorPeak, bVelDisp,&
                           bStreamDisp, bAngDisp,bOldFile, bFileBathy, filter_needed
   real(kind=dp)        :: x, y, u, v, r, u2v2, R_min, R_max, stdi, stdj, rhoC, npx, tmp, meanu, meanv,&
                           stdu, stdv, trsctA, trsctB, meanstw, stdstw
   character(len=160)   :: BaseName, line
   integer              :: lRef, lAvg, lPiv, lFil, lIn, lOut, lBath
   integer              :: i, ios, bsize, usp, nimg, npoints, k, l
   character(len=:), allocatable                :: NomIn, NomOut, list_avg_file
   real(kind=dp),dimension(:,:), allocatable    :: lstx, lsty, lstu, lstv, lstr, lstAr, lstnpx, list_points,&
                                                   lstZero, lstuOut, lstvOut
   logical,dimension(:,:), allocatable          :: xmedian_mask, ymedian_mask, correlation_mask,&
                                                   norm_mask, vx_mask, vy_mask, correlation_peak_mask,&
                                                   udispersion_mask, vdispersion_mask, streamwisedisp_mask,&
                                                   angulardisp_mask, intermediate_mask,final_mask ! masks for filtering
   type(kdtree2_result), pointer    :: idxs(:) ! results for qtree search
   type(kdtree2), pointer           :: tree ! the qtree

   open(newunit=lRef,file=trim(dir1)//'/'//img_ref,status='old')
   read(lRef,*)
   read(lRef,*) xmin,ymin
   read(lRef,*)
   read(lRef,*) xmax,ymax
   read(lRef,*)
   read(lRef,*) resol
   close (lRef)


! Read the PIV parameters
   open(newunit=lPiv,file=trim(dir1)//'/'//PIV_param,status='old')
   do i = 1, 8
      read(lPiv,*)
   enddo
   read(lPiv,'(a)',iostat=ios) line ; read(lPiv,*)
   if (present(dt_in)) then
     Dt = dt_in
   else
     read(line, *,iostat=ios)Dt, usp
     if (ios .ne. 0 .or. usp <= 0) usp = 1
     Dt = Dt * usp
   endif
   close (lPiv)
! END Read the PIV parameters

! Read the filters parameters
   inquire(file=trim(dir1)//'/'//filters, exist=filter_needed)
   if (filter_needed) then
      open(newunit=lFil,file=trim(dir1)//'/'//filters,status='old')
      read(lFil,*)
      read(lFil,*)
      read(lFil,*) bCor, R_min, R_max
      read(lFil,*)
      read(lFil,*) bNorm, smin, smax
      read(lFil,*)
      read(lFil,*) bVx, vxmin, vxmax
      read(lFil,*)
      read(lFil,*) bVy, vymin, vymax
      read(lFil,*)
      read(lFil,*) bMedTest, epsi, r0min, n_neighbor, dist_max
      read(lFil,*)
      read(lFil,*) bCorPeak, rcut, rhomax
      read(lFil,*)
      read(lFil,*) bVelDisp, nstdvel
      read(lFil,*)
      read(lFil,*) bStreamDisp, covmax
      read(lFil,*)
      read(lFil,*) bAngDisp, circvarmax
      read(lFil,*)
      read(lFil,*) aggregType
      close (lFil)
    ! END Read the filters parameters
  else ! default
     write(error_unit,'(a)') '---> Warning: no filters.dat file found, using default parameters'
     bcor = .true.
     R_min = 0.4_dp; R_max = 0.98_dp
     bNorm = .true.
     smin = 0._dp; smax = 1.E30_dp
     bVx = .true.
     vxmin = -1.E30_dp;  vxmax = +1.E30_dp
     bVy = .true.
     vymin = -1.E30_dp;  vymax = +1.E30_dp
     bMedTest = .false.
     bCorPeak = .false.
     bVelDisp = .false.
     bStreamDisp = .false.
     bAngDisp = .false.
  endif

! Check if transect data are available (in case of streamwise dispersion filter is used)
if (bStreamDisp) then
  inquire(file = trim(dir1)//'/bathy_p.dat', exist = bFileBathy)
  if (bFileBathy) then
    open(newunit=lBath,file=trim(dir1)//'/bathy_p.dat',status='old')
    do i = 1,4
      read(lBath,*)
    enddo
    read(lBath,*) trsctA, trsctB ! read transect orientation vector coordinates
  else
    write(error_unit,'(2a)') 'Erreur, fichier bathy_p.dat absent'
    stop ERR_STREAMWISE_FILTER_NO_TRANSECT
  endif
  close(lBath)
endif


   ! Read+count all data files listed in list_avg_files
   allocate(character(len=len_trim(dir1)+13) :: list_avg_file)
   list_avg_file = trim(dir1)//'/'//list_avg
   open(newunit=lAvg,file=trim(list_avg_file),status='old')
   bsize = 0
   nimg = 0
   do
      read(lAvg,*,iostat=ios) BaseName
      if (is_iostat_end(ios)) exit
      if (ios /= 0) then
          write(error_unit,'(2a)') 'Erreur de lecture du fichier ',trim(list_avg_file)
          stop ERR_READ_LIST_AVG
      endif
      nimg = nimg + 1
      bsize = max(bsize,len_trim(BaseName))
   enddo
   rewind(lAvg)
   allocate(character(len=len_trim(dir2)+bsize+20) :: NomIn, NomOut)

   ! Open last data file to get the number of velocity points
    NomIn = trim(dir2)//'/'//vel_raw//'/'//trim(BaseName)
    open(newunit=lIn,file=trim(NomIn),status='old')
    npoints = 0
    do
        read(lIn,*,iostat=ios)
        if (is_iostat_end(ios)) exit
        if (ios /= 0) then
            write(error_unit,'(2a)') 'Erreur de lecture du fichier ', trim(NomIn)
            stop ERR_READ_LIST_AVG
        endif
        npoints = npoints + 1
    enddo
    rewind(lIn)
    ! Check if the file contains 8 columns, otherwise it's an older piv.dat file
    do k = 1,npoints
        read(lIn,*,iostat=ios) tmp,tmp,tmp,tmp,tmp,tmp,tmp,tmp
        if (is_iostat_end(ios)) then
            bOldFile = .true.
            exit
        endif
    enddo
    close(lIn)

    ! Allocate data tables
    allocate(lstx(npoints,nimg),lsty(npoints,nimg),lstu(npoints,nimg),lstv(npoints,nimg),lstr(npoints,nimg)&
    ,lstAr(npoints,nimg),lstnpx(npoints,nimg),lstuOut(npoints,nimg),lstvOut(npoints,nimg),lstZero(npoints,nimg))
    allocate(list_points(2,npoints))
    allocate(idxs(n_neighbor+1))
    allocate(xmedian_mask(npoints,nimg),&
             ymedian_mask(npoints,nimg),&
             correlation_mask(npoints,nimg),&
             norm_mask(npoints,nimg),&
             vx_mask(npoints,nimg),&
             vy_mask(npoints,nimg),&
             correlation_peak_mask(npoints,nimg),&
             udispersion_mask(npoints,nimg),&
             vdispersion_mask(npoints,nimg),&
             streamwisedisp_mask(npoints,nimg),&
             angulardisp_mask(npoints,nimg),&
             intermediate_mask(npoints,nimg),&
             final_mask(npoints,nimg))
    xmedian_mask(:,:) = .true.
    ymedian_mask(:,:) = .true.
    correlation_mask(:,:) = .true.
    norm_mask(:,:) = .true.
    vx_mask(:,:) = .true.
    vy_mask(:,:) = .true.
    correlation_peak_mask(:,:) = .true.
    udispersion_mask(:,:) = .true.
    vdispersion_mask(:,:) = .true.
    streamwisedisp_mask(:,:) = .true.
    angulardisp_mask(:,:) = .true.
    intermediate_mask(:,:) = .true.
    final_mask(:,:) = .true.
    lstZero(:,:) = 0.0D0

    ! Fill tables with data
    do k = 1, nimg
        write(*,*) 'Initialisation...',(k*100.0)/nimg,"%"
      read(lAvg,*,iostat=ios) BaseName
      if (ios /= 0) then
          write(error_unit,'(2a)') 'Erreur de lecture du fichier ',trim(list_avg_file)
          stop ERR_READ_LIST_AVG
      endif
      ! Open data file
      NomIn = trim(dir2)//'/'//vel_raw//'/'//trim(BaseName)
      open(newunit=lIn,file=trim(NomIn),status='old')
      ! Run over data file and add data in tables
      do l = 1,npoints

        if (bOldFile) then
            read(lIn,*,iostat=ios) x, y, u, v, lstr(l,k)
        else
            read(lIn,*,iostat=ios) x, y, u, v, lstr(l,k), stdi, stdj, lstAr(l,k)
        end if
        if (ios /= 0) then
            write(error_unit,'(2a)') 'Erreur de lecture du fichier ', trim(NomIn)
            stop ERR_READ_LIST_AVG
        endif
        lsty(l,k) = y*resol+xmin
        lstx(l,k) = x*resol+ymin
        lstu(l,k) = (u*resol)/Dt
        lstv(l,k) = (v*resol)/Dt
        lstnpx(l,k) = sqrt(u**2+v**2) ! Pixel norm of disp.
      enddo
      close(lIn)
    enddo
    rewind(lAvg)

    ! Build kd tree for median test
    if (bMedTest)then
        write(*,*) 'Construction KDTree...'
        ! Run over files
        ! Apply median test (Westerweel and Scarano 2005) to remove spurious vectors.
        ! Use KDTree to identify neighbors
        list_points(1,:) = lstx(:,1)
        list_points(2,:) = lsty(:,1)
        tree => kdtree2_create(list_points,sort=.true.,rearrange=.true.)
        write(*,*) 'KDTree OK'
        end if

    ! Apply filters : median test, correl/velocity thresholds, correl peak width thresholds
    do k = 1, nimg
      write(*,*) 'Run filters...',(k*100.0)/nimg,"%"
      ! Run over vel points
       do l = 1,npoints
          x   = lstx(l,k)
          y   = lsty(l,k)
          u   = lstu(l,k) ! u -> vy
          v   = lstv(l,k) ! v -> vx
          r   = lstr(l,k)
          npx = lstnpx(l,k)
          u2v2 = sqrt(u**2+v**2)

          if (bOldFile) then
             rhoC = -1 ! Force rhoC to -1 to cancel filter (temporary solution) GB
          else
             rhoC = sqrt(lstAr(l,k)/3.141516) ! Radius of correlation pic at 0.8*max, expressed in m
          end if

          ! median test
          if (bMedTest) then
             ! Query tree to get n_neighbor around point l
             call kdtree2_n_nearest_around_point(tree,l,0,n_neighbor+1,idxs)
             !! results in idxs with idxs%idx the index and idxs%dist the SQUARE distance
             ymedian_mask(l,k) = median_filter(lstu(:,k), n_neighbor+1, idxs, epsi, u, r0min)
             xmedian_mask(l,k) = median_filter(lstv(:,k), n_neighbor+1, idxs, epsi, v, r0min)
          endif

          ! Correlation filter
          if (bCor) then
             correlation_mask(l,k) = .not.((r.gt.R_max).or.(r.lt.R_min))
          endif

          ! Norm filter
          if (bNorm) then
             norm_mask(l,k) = .not.((u2v2.gt.smax).or.(u2v2.lt.smin))
          endif

          ! Vx filter
          if (bVx) then
             Vx_mask(l,k) = .not.((v.gt.vxmax).or.(v.lt.vxmin))
          endif

          ! Vy filter
          if (bVy) then
             vy_mask(l,k) = .not.((u.gt.vymax).or.(u.lt.vymin))
          endif

          ! Correlation peak width filter
          if (bCorPeak) then
             correlation_peak_mask(l,k) = .not.(rhoC.gt.(rhomax*npx))
          endif
        enddo
    enddo
    ! For application of the first filters
    intermediate_mask = ymedian_mask &
                        .and.xmedian_mask &
                        .and.correlation_mask &
                        .and.norm_mask &
                        .and.vx_mask &
                        .and.vy_mask &
                        .and.correlation_peak_mask

    ! Another loop to apply dispersion filters at each point,
    ! taking into account the results of the previous filters
    do l = 1,npoints
    write(*,*) 'Run dispersion filters...',(l*100.0)/npoints,"%"
      ! Temporal dispersion filter
      if (bVelDisp) then
         !! apply on u
         if (count(intermediate_mask(l,:)) .gt. 1) then
            meanu = sum(lstu(l,:), mask = intermediate_mask(l,:))/count(intermediate_mask(l,:))
            stdu  = sqrt((sum((lstu(l,:)-meanu)**2, mask = intermediate_mask(l,:)))/(count(intermediate_mask(l,:))-1))

            udispersion_mask(l,:) = .not.(lstu(l,:).gt.meanu+(nstdvel*stdu)).or.(lstu(l,:).lt.meanu-(nstdvel*stdu))
               !! apply on v
            meanv = sum(lstv(l,:),mask = intermediate_mask(l,:))/count(intermediate_mask(l,:))
            stdv  = sqrt((sum((lstv(l,:)-meanv)**2, mask = intermediate_mask(l,:)))/(count(intermediate_mask(l,:))-1))

            vdispersion_mask(l,:) = .not.(lstv(l,:).gt.meanv+(nstdvel*stdv)).or.(lstv(l,:).lt.meanv-(nstdvel*stdv))
         else
            udispersion_mask(l,:) = .false.
            vdispersion_mask(l,:) = .false.
         endif
      endif
         if (bStreamDisp) then
            ! Streamwise dispersion filter
            if ((count(intermediate_mask(l,:) &
                        .and.udispersion_mask(l,:) &
                        .and.vdispersion_mask(l,:)) .gt. 1)) then
               meanstw = sum((-trsctB*lstv(l,:)+trsctA*lstu(l,:)), mask = intermediate_mask(l,:) &
                                                                     .and.udispersion_mask(l,:) &
                                                                     .and.vdispersion_mask(l,:) &
                           )/count(intermediate_mask(l,:) &
                              .and.udispersion_mask(l,:) &
                              .and.vdispersion_mask(l,:))
               if (abs(meanstw) > 0.0) then

                  stdstw = sqrt((sum(((-trsctB*lstv(l,:)+trsctA*lstu(l,:))-meanstw)**2, mask = intermediate_mask(l,:) &
                                                                                          .and.udispersion_mask(l,:) &
                                                                                          .and.vdispersion_mask(l,:) &
                                    ) &
                              )/(count(intermediate_mask(l,:) &
                                    .and.udispersion_mask(l,:) &
                                    .and.vdispersion_mask(l,:))-1))

                  streamwisedisp_mask(l,:) = .not.((stdstw/meanstw).gt.covmax)
               else
                  streamwisedisp_mask(l,:) = .false.
               endif
            else
               streamwisedisp_mask(l,:) = .false.
            endif
         endif
            if (bAngDisp) then
            ! Angular dispersion filter
            angulardisp_mask(l,:) = .not.(circular_variance(lstu(l,:),lstv(l,:)).gt.circvarmax)
         endif
    enddo

    ! Build final filter mask
    final_mask = intermediate_mask &
                .and.udispersion_mask &
                .and.vdispersion_mask &
                .and.streamwisedisp_mask &
                .and.angulardisp_mask

    ! Apply filters!!
    lstuOut = merge(lstu,lstZero,final_mask)
    lstvOut = merge(lstv,lstZero,final_mask)

    ! Export masks results
    call save_filter_mask(trim(dir1)//'/median_test_fmask.dat',xmedian_mask.and.ymedian_mask,nimg)
    call save_filter_mask(trim(dir1)//'/vx_fmask.dat',vx_mask,nimg)
    call save_filter_mask(trim(dir1)//'/vy_fmask.dat',vy_mask,nimg)
    call save_filter_mask(trim(dir1)//'/norm_fmask.dat',norm_mask,nimg)
    call save_filter_mask(trim(dir1)//'/corr_peak_width_fmask.dat',correlation_peak_mask,nimg)
    call save_filter_mask(trim(dir1)//'/temporal_disp_fmask.dat',udispersion_mask.and.vdispersion_mask,nimg)
    call save_filter_mask(trim(dir1)//'/streamwise_disp_fmask.dat',streamwisedisp_mask,nimg)
    call save_filter_mask(trim(dir1)//'/angular_disp_fmask.dat',angulardisp_mask,nimg)

    ! Export results
    do k = 1, nimg
        write(*,*) 'Write results...',(k*100.0)/nimg,"%"
        read(lAvg,*,iostat=ios) BaseName
        if (is_iostat_end(ios)) exit
        if (ios /= 0) then
            write(error_unit,'(2a)') 'Erreur de lecture du fichier ',trim(list_avg_file)
            stop ERR_READ_LIST_AVG
        endif
        ! Open output file
        NomOut = trim(dir2)//'/'//vel_filter//'/'//'filter_'//trim(BaseName)
        open(newunit=lOut,file=trim(NomOut),status='unknown')
        ! Write results
        do l = 1,npoints
            write(lOut,*) lsty(l,k), lstx(l,k), lstvOut(l,k), lstuOut(l,k), lstr(l,k)
        enddo
        close(lOut)
    enddo
    close(lAvg)

    ! Dellocate data tables
    deallocate(lstx,lsty,lstu,lstv,lstr,lstAr,lstnpx,lstZero,lstuOut,lstvOut)
    deallocate(list_points)
    deallocate(xmedian_mask,ymedian_mask,correlation_mask,norm_mask,&
               vx_mask,vy_mask,correlation_peak_mask,udispersion_mask,&
               vdispersion_mask,streamwisedisp_mask,angulardisp_mask,&
               intermediate_mask,final_mask)
end subroutine sub_filter

subroutine save_filter_mask(filename,mask,nimg)
    ! Function to export mask data
    character(len=*), intent(in)           :: filename
    logical, dimension(:,:), intent(in)    :: mask
    integer, intent(in)                    :: nimg
    integer                                :: lf,k

    open(newunit=lf,file=trim(filename),status='unknown')
    do k = 1,nimg
        write(lf,*) mask(:,k)
    enddo
    close(lf)

end subroutine

function median_filter(array, idxs_size, idxs, eps, x, thres)
    use kdtree2_module, only: kdtree2_result
    use lspiv_parameter, only: median

    implicit none
    ! protype
    real(kind=dp), intent(in), dimension(:)     :: array
    integer, intent(in)                         :: idxs_size
    type(kdtree2_result), intent(in), pointer   :: idxs(:)
    real(kind=dp), intent(in)                   :: eps, x, thres
    logical                                     :: median_filter
    ! local variables
    real(kind=dp), dimension(:), allocatable    :: array_tmp
    real(kind=dp)                               :: m, max, residual
    integer                                     :: i, j

    if (idxs_size < 1) then
        median_filter = .false.
        return
    endif

    allocate(array_tmp(idxs_size))
    do i=1,idxs_size
        array_tmp(i) = array(idxs(i)%idx)
    enddo

    !!! ref velocity !!!
    m = median(array_tmp)
    !!! end ref velocity !!!

    !!! residual !!!
    do i=1,idxs_size
        array_tmp(i) = array(idxs(i)%idx)-m
    enddo
    residual = abs(x-m) / (median(array_tmp)+eps)
    !!! end residual !!!
    deallocate(array_tmp)

    if (residual > thres) then
        median_filter = .false.
    else
        median_filter = .true.
    endif
end function median_filter

! circular variance
function circular_variance(x, y)
   implicit none
   real(kind=dp), dimension(:)              :: x, y
   real(kind=dp), dimension(:), allocatable :: angle
   real(kind=dp)                            :: circular_variance
   real(kind=dp)                            :: mean

   allocate(angle(size(x)))
   angle(:) = atan2(y(:),x(:))

   mean = circular_mean(angle)
   circular_variance = 1.0D0 - sum(cos(angle - mean))/real(size(angle))
   deallocate(angle)
end function circular_variance

! circular mean
function circular_mean(angle)
   implicit none
   real(kind=dp), dimension(:) :: angle
   real(kind=dp) :: circular_mean
   circular_mean = atan2(sum(sin(angle(1:size(angle)))), &
                         sum(cos(angle(1:size(angle)))))
end function circular_mean

end module mod_filter
