#include "MAPL_Generic.h"
!-------------------------------------------------------------------------
!         GEOS-Chem High Performance Global Chemical Transport Model
!-------------------------------------------------------------------------
!BOP
!
! !MODULE: GCHPctmEnv_GridCompMod
!
! !DESCRIPTION: Cinderella component to compute derived variables to pass to
! advection
!\\
!\\
! !INTERFACE:
!
module GCHPctmEnv_GridComp
!
! !USES:
!
   use ESMF
   use MAPL_Mod
   use FV_StateMod, only : fv_computeMassFluxes, fv_getVerticalMassFlux
   use GEOS_FV3_UtilitiesMod, only : A2D2C
   use m_set_eta,  only : set_eta
   use pFlogger, only: logging, Logger
   
   implicit none
   private
!
! !PUBLIC MEMBER FUNCTIONS:
!
   public  :: SetServices
!
! !PRIVATE MEMBER FUNCTIONS:
!
   private :: Initialize
   private :: Run
   private :: prepare_ple_exports
   private :: prepare_sphu_export
   private :: prepare_massflux_exports
   private :: calculate_ple
!
! !PUBLIC DATA MEMBERS:
!
   logical, public :: import_mass_flux_from_extdata = .false.
!
! !PRIVATE DATA MEMBERS:
!
   integer, parameter :: r8     = 8
   integer, parameter :: r4     = 4
   
   logical :: meteorology_vertical_index_is_top_down
   integer :: use_total_air_pressure_in_advection
   integer :: correct_mass_flux_for_humidity
   
   class(Logger), pointer :: lgr => null()
!
! !REMARKS:
!  This file was adapted from a GEOS file developed at NASA GMAO.
!                                                                             .
!  NOTES:
!  - The abbreviation "PET" stands for "Persistent Execution Thread".
!    It is a synomym for CPU.
!
! !REVISION HISTORY:
!  06 Dec 2009 - A. da Silva - Initial version this file was adapted from
!  08 Sep 2014 - M. Long - Modification to calculate pressure at vertical
!                          grid edges from hybrid coordinates
!  24 Jan 2019 - E. Lundgren - Modification for compatibility with ESMF v7.1.0r
!  See https://github.com/geoschem/geos-chem for history since GCHP version 12.5
!
!EOP
!------------------------------------------------------------------------------
!BOC
   contains
!EOC

!-------------------------------------------------------------------------
!         GEOS-Chem High Performance Global Chemical Transport Model
!-------------------------------------------------------------------------
!BOP
!
! !IROUTINE: SetServices -- Sets ESMF services for this component
!
! !INTERFACE:
!
   subroutine SetServices(GC, RC)
!
! !INPUT/OUTPUT PARAMETERS
!
      type(ESMF_GridComp), intent(INOUT) :: GC  ! gridded component
!
! !OUTPUT PARAMETERS
!
      integer, intent(OUT)               :: RC  ! return code
!
! !DESCRIPTION:
!   The SetServices for the CTM needs to register its Initialize and Run.
!   It uses the MAPL_Generic construct for defining state specs.
!
!EOP
!-------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
      integer           :: STATUS
      type(ESMF_Config) :: CF

      character(len=ESMF_MAXSTR) :: COMP_NAME, msg
      character(len=ESMF_MAXSTR) :: IAm = 'SetServices'

      !================================
      ! SetServices starts here
      !================================
      
      ! Get gridded component name and set-up traceback handle
      ! -----------------------------------------------------------------
      call ESMF_GridCompGet(GC, NAME=COMP_NAME, CONFIG=CF, RC=STATUS)
      _VERIFY(STATUS)
      Iam = trim(COMP_NAME) // TRIM(Iam)
      lgr => logging%get_logger('GCHPctmEnv')
      
      ! Get whether to import mass fluxes from ExtData or derive from winds
      ! -----------------------------------------------------------------
      call ESMF_ConfigGetAttribute(CF,                                     &
                                   value=import_mass_flux_from_extdata,    &
                                   label='IMPORT_MASS_FLUX_FROM_EXTDATA:', &
                                   Default=.false.,                        &
                                   __RC__)
      if (import_mass_flux_from_extdata) then
         msg = 'Configured to import mass fluxes from ''ExtData'''
      else
         msg = 'Configured to derive and export mass flux and courant numbers'
      end if
      call lgr%info(msg)
      
      ! Register services for this component
      ! -----------------------------------------------------------------
      call MAPL_GridCompSetEntryPoint(gc, ESMF_METHOD_INITIALIZE, Initialize, &
                                      RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_GridCompSetEntryPoint(gc, ESMF_METHOD_RUN, Run, RC=STATUS)
      _VERIFY(STATUS)
      
      ! Define Import state
      ! -----------------------------------------------------------------
      call lgr%debug('Adding import specs')
      call MAPL_AddImportSpec(gc, &
                              SHORT_NAME='PS1', &
                              LONG_NAME='pressure_at_surface_before_advection',&
                              UNITS='hPa', &
                              DIMS=MAPL_DimsHorzOnly, &
                              VLOCATION=MAPL_VLocationEdge, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddImportSpec(gc, &
                              SHORT_NAME='PS2', &
                              LONG_NAME='pressure_at_surface_after_advection',&
                              UNITS='hPa', &
                              DIMS=MAPL_DimsHorzOnly, &
                              VLOCATION=MAPL_VLocationEdge, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddImportSpec(gc, &
                              SHORT_NAME='PS2', &
                              LONG_NAME='pressure_at_surface_after_advection', &
                              UNITS='hPa', &
                              DIMS=MAPL_DimsHorzOnly, &
                              VLOCATION=MAPL_VLocationEdge, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddImportSpec(gc, &
                              SHORT_NAME='SPHU1', &
                              LONG_NAME='specific_humidity_before_advection', &
                              UNITS='kg kg-1', &
                              DIMS=MAPL_DimsHorzVert, &
                              VLOCATION=MAPL_VLocationCenter, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddImportSpec(gc, &
                              SHORT_NAME='SPHU2', &
                              LONG_NAME='specific_humidity_after_advection',  &
                              UNITS='kg kg-1', &
                              DIMS=MAPL_DimsHorzVert, &
                              VLOCATION=MAPL_VLocationCenter, &
                              RC=STATUS)
      _VERIFY(STATUS)

      ! Different imports depending on where mass fluxes will come from
      if ( import_mass_flux_from_extdata ) then

         call MAPL_AddImportSpec(gc, &
                                 SHORT_NAME='MFXC', &
                                 LONG_NAME='pressure_weighted_xward_mass_flux',&
                                 UNITS='Pa m+2 s-1', &
                                 DIMS=MAPL_DimsHorzVert, &
                                 VLOCATION=MAPL_VLocationCenter, &
                                 RC=STATUS)
         VERIFY_(STATUS)
         call MAPL_AddImportSpec(gc, &
                                 SHORT_NAME='MFYC', &
                                 LONG_NAME='pressure_weighted_yward_mass_flux',&
                                 UNITS='Pa m+2 s-1', &
                                 DIMS=MAPL_DimsHorzVert, &
                                 VLOCATION=MAPL_VLocationCenter, &
                                 RC=STATUS)
         VERIFY_(STATUS)
         call MAPL_AddImportSpec(gc, &
                                 SHORT_NAME='CXC', &
                                 LONG_NAME='xward_accumulated_courant_number', &
                                 UNITS='', &
                                 DIMS=MAPL_DimsHorzVert, &
                                 VLOCATION=MAPL_VLocationCenter, &
                                 RC=STATUS)
         VERIFY_(STATUS)
         call MAPL_AddImportSpec(gc, &
                                 SHORT_NAME='CYC', &
                                 LONG_NAME='yward_accumulated_courant_number', &
                                 UNITS='', &
                                 DIMS=MAPL_DimsHorzVert, &
                                 VLOCATION=MAPL_VLocationCenter, &
                                 RC=STATUS)
         VERIFY_(STATUS)

      else

         call MAPL_AddImportSpec(gc, &
                                 SHORT_NAME='UA', &
                                 LONG_NAME='eastward_wind_on_A-Grid', &
                                 UNITS='m s-1', &
                                 STAGGERING=MAPL_AGrid, &
                                 ROTATION=MAPL_RotateLL, &
                                 DIMS=MAPL_DimsHorzVert, &
                                 VLOCATION=MAPL_VLocationCenter, &
                                 RC=STATUS)
         _VERIFY(STATUS)
         call MAPL_AddImportSpec(gc, &
                                 SHORT_NAME='VA', &
                                 LONG_NAME='northward_wind_on_A-Grid', &
                                 UNITS='m s-1', &
                                 STAGGERING=MAPL_AGrid, &
                                 ROTATION=MAPL_RotateLL, &
                                 DIMS=MAPL_DimsHorzVert, &
                                 VLOCATION=MAPL_VLocationCenter, &
                                 RC=STATUS)
         _VERIFY(STATUS)

      endif
      
      ! Define Export State
      ! -----------------------------------------------------------------
      call lgr%debug('Adding export specs')
      call MAPL_AddExportSpec(gc, &
                              SHORT_NAME='SPHU0', &
                              LONG_NAME='specific_humidity_before_advection', &
                              UNITS='kg kg-1', &
                              PRECISION=ESMF_KIND_R8, &
                              DIMS=MAPL_DimsHorzVert, &
                              VLOCATION=MAPL_VLocationCenter, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddExportSpec(gc, &
                              SHORT_NAME='PLE0', &
                              LONG_NAME='pressure_at_layer_edges_before_advection',&
                              UNITS='Pa', &
                              PRECISION=ESMF_KIND_R8, &
                              DIMS=MAPL_DimsHorzVert, &
                              VLOCATION=MAPL_VLocationEdge, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddExportSpec(gc, &
                              SHORT_NAME='PLE1', &
                              LONG_NAME='pressure_at_layer_edges_after_advection', &
                              UNITS='Pa', &
                              PRECISION=ESMF_KIND_R8, &
                              DIMS=MAPL_DimsHorzVert, &
                              VLOCATION=MAPL_VLocationEdge, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddExportSpec(gc,                                    &
                              SHORT_NAME = 'DryPLE0',                &
                              LONG_NAME  = 'dry_pressure_at_layer_edges_before_advection',&
                              UNITS      = 'Pa',                     &
                              PRECISION  = ESMF_KIND_R8,             &
                              DIMS       = MAPL_DimsHorzVert,        &
                              VLOCATION  = MAPL_VLocationEdge,       &
                              RC=STATUS  )
      _VERIFY(STATUS)
      call MAPL_AddExportSpec(gc,                                   &
                              SHORT_NAME = 'DryPLE1',                &
                              LONG_NAME  = 'dry_pressure_at_layer_edges_after_advection',&
                              UNITS      = 'Pa',                     &
                              PRECISION  = ESMF_KIND_R8,             &
                              DIMS       = MAPL_DimsHorzVert,        &
                              VLOCATION  = MAPL_VLocationEdge,       &
                              RC=STATUS  )
      _VERIFY(STATUS)
      call MAPL_AddExportSpec(gc, &
                              SHORT_NAME='CX', &
                              LONG_NAME='xward_accumulated_courant_number', &
                              UNITS='', &
                              PRECISION=ESMF_KIND_R8, &
                              DIMS=MAPL_DimsHorzVert, &
                              VLOCATION=MAPL_VLocationCenter, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddExportSpec(gc, &
                              SHORT_NAME='CY', &
                              LONG_NAME='yward_accumulated_courant_number', &
                              UNITS='', &
                              PRECISION=ESMF_KIND_R8, &
                              DIMS=MAPL_DimsHorzVert, &
                              VLOCATION=MAPL_VLocationCenter, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddExportSpec(gc, &
                              SHORT_NAME='MFX', &
                              LONG_NAME='pressure_weighted_accumulated_xward_mass_flux', &
                              UNITS='Pa m+2 s-1', &
                              PRECISION=ESMF_KIND_R8, &
                              DIMS=MAPL_DimsHorzVert, &
                              VLOCATION=MAPL_VLocationCenter, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddExportSpec(gc, &
                              SHORT_NAME='MFY', &
                              LONG_NAME='pressure_weighted_accumulated_yward_mass_flux', &
                              UNITS='Pa m+2 s-1', &
                              PRECISION=ESMF_KIND_R8, &
                              DIMS=MAPL_DimsHorzVert, &
                              VLOCATION=MAPL_VLocationCenter, &
                              RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_AddExportSpec(gc, &
                              SHORT_NAME='UpwardsMassFlux', &
                              LONG_NAME='upward_mass_flux_of_air', &
                              UNITS='kg m-2 s-1', &
                              PRECISION=ESMF_KIND_R8, &
                              DIMS=MAPL_DimsHorzVert, &
                              VLOCATION=MAPL_VLocationEdge, &
                              RC=STATUS)
      _VERIFY(STATUS)

      ! Set profiling timers
      !-------------------------
      call lgr%debug('Adding timers')
      call MAPL_TimerAdd(gc, name="INITIALIZE", RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_TimerAdd(gc, name="RUN", RC=STATUS)
      _VERIFY(STATUS)
      
      call lgr%debug('Calling MAPL_GenericSetServices')

      ! Create children's gridded components and invoke their SetServices
      ! -----------------------------------------------------------------
      call MAPL_GenericSetServices(gc, RC=STATUS)
      _VERIFY(STATUS)
      
      _RETURN(ESMF_SUCCESS)
      
   end subroutine SetServices
!EOC
!-------------------------------------------------------------------------
!         GEOS-Chem High Performance Global Chemical Transport Model
!-------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Initialize -- Initialized method for composite the CTMder
!
! !INTERFACE:
!
   subroutine Initialize(GC, IMPORT, EXPORT, CLOCK, RC)
!
! !INPUT/OUTPUT PARAMETERS:
!
      type(ESMF_GridComp), intent(inout) :: GC     ! Gridded component 
      type(ESMF_State),    intent(inout) :: IMPORT ! Import state
      type(ESMF_State),    intent(inout) :: EXPORT ! Export state
      type(ESMF_Clock),    intent(inout) :: CLOCK  ! The clock
!
! !OUTPUT PARAMETERS:
!
      integer, optional,   intent(out)   :: RC     ! Error code
!
! !DESCRIPTION:
!  The Initialize method of the CTM Derived Gridded Component.
!
!EOP
!-------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
      integer                    :: comm
      character(len=ESMF_MAXSTR) :: COMP_NAME
      character(len=ESMF_MAXSTR) :: msg
      type(ESMF_Config)          :: CF
      type(ESMF_Grid)            :: esmfGrid
      type(ESMF_VM)              :: VM

      type(MAPL_MetaComp), pointer  :: ggState ! MAPL Generic State
      REAL, POINTER, DIMENSION(:,:) :: cellArea

      !================================
      ! Initialize starts here
      !================================

      __Iam__('Initialize')
      
      !  Get this gridded component name and set-up traceback handle
      ! -----------------------------------------------------------------
      call ESMF_GridCompGet(GC, NAME=COMP_NAME, CONFIG=CF, VM=VM, RC=STATUS)
      _VERIFY(STATUS)
      Iam = TRIM(COMP_NAME)//"::Initialize"
      
      !  Initialize MAPL_Generic
      ! -----------------------------------------------------------------
      call MAPL_GenericInitialize(gc, IMPORT, EXPORT, clock, RC=STATUS)
      _VERIFY(STATUS)
      
      !  Get internal MAPL_Generic state
      ! -----------------------------------------------------------------
      call MAPL_GetObjectFromGC(GC, ggState, RC=STATUS)
      _VERIFY(STATUS)

      ! Turn on timers
      ! -----------------------------------------------------------------
      call MAPL_TimerOn(ggSTATE, "TOTAL")
      call MAPL_TimerOn(ggSTATE, "INITIALIZE")
      
      ! Get grid-related information
      ! -----------------------------------------------------------------
      call ESMF_GridCompGet(GC, GRID=esmfGrid, rc=STATUS)
      _VERIFY(STATUS)
      
      ! Get whether meteorology vertical index is top down (native fields)
      ! or bottom up (GEOS-Chem processed fields)
      ! -----------------------------------------------------------------
      call ESMF_ConfigGetAttribute( &
                               CF,                                             &
                               value=meteorology_vertical_index_is_top_down,   &
                               label='METEOROLOGY_VERTICAL_INDEX_IS_TOP_DOWN:',&
                               Default=.false.,                                &
                               __RC__ )
      if (meteorology_vertical_index_is_top_down) then
         msg='Configured to expect ''top-down'' meteorological data'// &
             ' from ''ExtData'''
      else
         msg='Configured to expect ''bottom-up'' meteorological'// &
             ' data from ''ExtData'''
      end if
      call lgr%info(trim(msg))

      ! Get whether to use total or dry air pressure in advection
      ! -----------------------------------------------------------------
      call ESMF_ConfigGetAttribute( &
                               CF,                                             &
                               value=use_total_air_pressure_in_advection,      &
                               label='USE_TOTAL_AIR_PRESSURE_IN_ADVECTION:',   &
                               Default=0,                                      &
                               __RC__ )
      if ( use_total_air_pressure_in_advection > 0 ) then
         msg='Configured to use total air pressure in advection'
      else
         msg='Configured to use dry air pressure in advection'
      end if
      call lgr%info(trim(msg))

      ! Get whether to correct mass flux for humidity (convert total to dry)
      ! -----------------------------------------------------------------
      call ESMF_ConfigGetAttribute( &
                               CF,                                             &
                               value=correct_mass_flux_for_humidity,           &
                               label='CORRECT_MASS_FLUX_FOR_HUMIDITY:',        &
                               Default=1,                                      &
                               __RC__ )
      if ( correct_mass_flux_for_humidity > 0 ) then
         msg='Configured to correct native mass flux (if using) for humidity'
      else
         msg='Configured to not correct native mass flux (if using) for humidity'
      end if
      call lgr%info(trim(msg))

      ! Turn off timers
      ! -----------------------------------------------------------------
      call MAPL_TimerOff(ggSTATE,"INITIALIZE")
      call MAPL_TimerOff(ggSTATE,"TOTAL")
      
      _RETURN(ESMF_SUCCESS)
      
   end subroutine Initialize
!EOC
!-------------------------------------------------------------------------
!         GEOS-Chem High Performance Global Chemical Transport Model
!-------------------------------------------------------------------------
!BOP
!
! !INTERFACE:
!
   subroutine Run(GC, IMPORT, EXPORT, CLOCK, RC)
!
! !INPUT/OUTPUT PARAMETERS:
!
      type(ESMF_GridComp), intent(inout) :: GC     ! Gridded component 
      type(ESMF_State),    intent(inout) :: IMPORT ! Import state
      type(ESMF_State),    intent(inout) :: EXPORT ! Export state
      type(ESMF_Clock),    intent(inout) :: CLOCK  ! The clock
!
! !OUTPUT PARAMETERS:
!
      integer, optional,   intent(out) :: RC       ! Error code
!
! !DESCRIPTION:
! The Run method of the derived variables CTM Gridded Component.
!
!EOP
!-------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
      integer                      :: STATUS
      integer                      :: ndt
      character(len=ESMF_MAXSTR)   :: IAm = "Run"
      character(len=ESMF_MAXSTR)   :: COMP_NAME
      type(MAPL_MetaComp), pointer :: ggState
      type(ESMF_Grid)              :: esmfGrid
      real(r8)                     :: dt
      real(r8), pointer            :: PLE(:,:,:) ! Edge pressures

      ! Saved variables
      logical, save :: firstRun = .true.
      
#ifdef ADJOINT
      integer :: reverseTime
#endif

      !================================
      ! Run starts here
      !================================
      
      ! Get this component's name and set-up traceback handle.
      call ESMF_GridCompGet(GC, name=COMP_NAME, Grid=esmfGrid, RC=STATUS)
      _VERIFY(STATUS)
      Iam = trim(COMP_NAME) // TRIM(Iam)
      
      ! Get internal MAPL_Generic state
      call MAPL_GetObjectFromGC(GC, ggState, RC=STATUS)
      _VERIFY(STATUS)

      ! Turn on timers
      call MAPL_TimerOn(ggState,"TOTAL")
      call MAPL_TimerOn(ggState,"RUN")
      
      ! Retrieve timestep [s] and store as real
      call MAPL_GetResource( ggState,   &
                             ndt,       &
                             'RUN_DT:', &
                             default=0, &
                             RC=STATUS )
      _VERIFY(STATUS)
      dt = ndt
      
#ifdef ADJOINT
      ! Modifications for running time backwards in adjoint
      call MAPL_GetResource( ggState,         &
                             reverseTime,     &
                             'REVERSE_TIME:', &
                             default=0,       &
                             RC=STATUS )
      _VERIFY(STATUS)
      IF(MAPL_Am_I_Root()) WRITE(*,*) ' GIGCenv REVERSE_TIME: ', reverseTime
      IF(reverseTime .eq. 1) THEN
         WRITE(*,*) ' GIGCenv swapping timestep sign.'
         dt = -dt
      ENDIF
#endif

      ! Compute the exports
      call prepare_ple_exports(IMPORT, EXPORT, PLE, RC=STATUS)
      _VERIFY(STATUS)
      call prepare_sphu_export(IMPORT, EXPORT, RC=STATUS)
      _VERIFY(STATUS)
      call prepare_massflux_exports(IMPORT, EXPORT, PLE, dt, RC=STATUS)
      _VERIFY(STATUS)

      ! Turn off timers
      call MAPL_TimerOff(ggState,"RUN")
      call MAPL_TimerOff(ggState,"TOTAL")
      
      _RETURN(ESMF_SUCCESS)

   end subroutine Run
!EOC
!-------------------------------------------------------------------------
!         GEOS-Chem High Performance Global Chemical Transport Model
!-------------------------------------------------------------------------
!BOP
!
! !INTERFACE:
!
   subroutine prepare_ple_exports(IMPORT, EXPORT, PLE, RC)
!
! !INPUT/OUTPUT PARAMETERS:
!
      type(ESMF_State), intent(inout)  :: IMPORT
      type(ESMF_State), intent(inout)  :: EXPORT
!
! !OUTPUT PARAMETERS:
!
      real(r8), intent(out), pointer   :: PLE(:,:,:) ! Edge pressures
      integer,  intent(out), optional  :: RC
!
! !DESCRIPTION: Compute pressure edge exports for use in advection.
!
!EOP
!-------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
      integer :: LM
      integer :: STATUS
      real,     pointer, dimension(:,:)   ::  PS1_IMPORT    => null()
      real,     pointer, dimension(:,:)   ::  PS2_IMPORT    => null()
      real,     pointer, dimension(:,:,:) :: SPHU1_IMPORT    => null()
      real,     pointer, dimension(:,:,:) :: SPHU2_IMPORT    => null()
      real(r8), pointer, dimension(:,:,:) :: PLE0_EXPORT    => null()
      real(r8), pointer, dimension(:,:,:) :: PLE1_EXPORT    => null()
      real(r8), pointer, dimension(:,:,:) :: DryPLE0_EXPORT => null()
      real(r8), pointer, dimension(:,:,:) :: DryPLE1_EXPORT => null()

      !================================
      ! prepare_ple_exports starts here
      !================================
      ! NB: Input at ExtData is PS1 (before) and PS2 (after)
      !     Input at FV3 is PLE0 (before) and PLE1 (after)
      call lgr%debug('Preparing FV3 inputs PLE0 and PLE1')

      ! Get imports (real4)
      call MAPL_GetPointer(IMPORT, PS1_IMPORT,    'PS1', RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_GetPointer(IMPORT, PS2_IMPORT,    'PS2', RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_GetPointer(IMPORT, SPHU1_IMPORT,  'SPHU1', RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_GetPointer(IMPORT, SPHU2_IMPORT,  'SPHU2', RC=STATUS)
      _VERIFY(STATUS)

      ! Get exports (real8) and initialize
      call MAPL_GetPointer(EXPORT, PLE0_EXPORT,  'PLE0',  RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_GetPointer(EXPORT, PLE1_EXPORT,  'PLE1',  RC=STATUS)
      _VERIFY(STATUS)
      PLE0_EXPORT(:,:,:)  = 0.0d0
      PLE1_EXPORT(:,:,:)  = 0.0d0

      if ( use_total_air_pressure_in_advection < 1 ) then
         call MAPL_GetPointer(EXPORT, DryPLE0_EXPORT,  'DryPLE0',  RC=STATUS)
         _VERIFY(STATUS)
         call MAPL_GetPointer(EXPORT, DryPLE1_EXPORT,  'DryPLE1',  RC=STATUS)
         _VERIFY(STATUS)
         DryPLE0_EXPORT(:,:,:)  = 0.0d0
         DryPLE1_EXPORT(:,:,:)  = 0.0d0
      endif

      ! Set number of levels
      LM = size(PLE0_EXPORT,3) - 1

      ! Compute pressure edge exports from surface pressure and
      ! then convert from hPa to Pa and vertically flip so that level index
      ! is top-down (level 1 is TOA). The transformation is needed because
      ! calculate_ple returns bottom-up pressure as in [hPa] and advection
      ! expects top-down pressure in [Pa].

      ! Compute PLE0 from PS1 (naming mismatch between FV3 GEOS-Chem)
      call calculate_ple(PS1_IMPORT, PLE0_EXPORT)
      PLE0_EXPORT = 100.0d0 * PLE0_EXPORT
      PLE0_EXPORT = PLE0_EXPORT(:,:,LM:0:-1)

      ! Compute PLE1 from PS2 (naming mismatch between FV3 GEOS-Chem )
      call calculate_ple(PS2_IMPORT, PLE1_EXPORT)
      PLE1_EXPORT = 100.0d0 * PLE1_EXPORT
      PLE1_EXPORT = PLE1_EXPORT(:,:,LM:0:-1)

      ! Also compute dry pressures if using dry pressure in advection
      if ( use_total_air_pressure_in_advection < 1 ) then

         call calculate_ple(          &
              PS=PS1_IMPORT,          &
              PLE=DryPLE0_EXPORT,     &
              SPHU=SPHU1_IMPORT,      &
              topDownMet=meteorology_vertical_index_is_top_down )

         DryPLE0_EXPORT = 100.0d0 * DryPLE0_EXPORT
         DryPLE0_EXPORT = DryPLE0_EXPORT(:,:,LM:0:-1)

         call calculate_ple(          &
              PS=PS2_IMPORT,          &
              PLE=DryPLE1_EXPORT,     &
              SPHU=SPHU2_IMPORT,      &
              topDownMet=meteorology_vertical_index_is_top_down )

         DryPLE1_EXPORT = 100.0d0 * DryPLE1_EXPORT
         DryPLE1_EXPORT = DryPLE1_EXPORT(:,:,LM:0:-1)

      endif

      ! Set PLE output which will be used to compute mass fluxes in FV3
      if ( use_total_air_pressure_in_advection > 0 ) then
         PLE => PLE0_EXPORT
      else
         PLE => DryPLE0_Export
      endif

      _RETURN(ESMF_SUCCESS)

  end subroutine prepare_ple_exports
!EOC
!-------------------------------------------------------------------------
!         GEOS-Chem High Performance Global Chemical Transport Model
!-------------------------------------------------------------------------
!BOP
!
! !INTERFACE:
!
   subroutine prepare_sphu_export(IMPORT, EXPORT, RC)
!
! !INPUT/OUTPUT PARAMETERS:
!
      type(ESMF_State), intent(inout) :: IMPORT
      type(ESMF_State), intent(inout) :: EXPORT
!
! !OUTPUT PARAMETERS:
!
      integer, optional, intent(out)  :: RC
      integer :: LM
!
! !DESCRIPTION: Set SPHU export for advection. This is only done if using
! total rather than dry pressure in advection.
!
!EOP
!-------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
      integer :: STATUS
      real,     pointer, dimension(:,:,:) :: SPHU1_IMPORT => null()
      real(r8), pointer, dimension(:,:,:) :: SPHU0_EXPORT => null()

      !================================
      ! prepare_sphu_export starts here
      !================================

      ! NB: Input at ExtData is SPHU1 (before) and SPHU2 (after)
      !     Input at FV3 is SPHU0 (before) and SPHU1 (after)
      call lgr%debug('Preparing FV3 input SPHU0')

      ! Get imports (real4)
      call MAPL_GetPointer(IMPORT, SPHU1_IMPORT, 'SPHU1', RC=STATUS)
      _VERIFY(STATUS)

      ! Get exports (real8) and initialize to 0
      call MAPL_GetPointer(EXPORT, SPHU0_EXPORT, 'SPHU0', RC=STATUS)
      _VERIFY(STATUS)
      SPHU0_EXPORT(:,:,:) = 0.0d0

      ! Set number of levels
      LM = size(SPHU1_IMPORT, 3)

      ! Set export as copy of import casted to real8 and set vertical index
      ! as top-down (level 1 corresponds to TOA)
      if (meteorology_vertical_index_is_top_down) then 
         SPHU0_EXPORT = dble(SPHU1_IMPORT)
      else
         SPHU0_EXPORT(:,:,:) = dble(SPHU1_IMPORT(:,:,LM:1:-1))
      end if

      _RETURN(ESMF_SUCCESS)

   end subroutine prepare_sphu_export
!EOC
!-------------------------------------------------------------------------
!         GEOS-Chem High Performance Global Chemical Transport Model
!-------------------------------------------------------------------------
!BOP
!
! !INTERFACE:
!
   subroutine prepare_massflux_exports(IMPORT, EXPORT, PLE, dt, RC)
!
! !INPUT PARAMETERS:
!
      real(r8), intent(in), pointer   :: PLE(:,:,:) ! Edge pressures
      real(r8), intent(in)            :: dt
!
! !INPUT/OUTPUT PARAMETERS:
!
      type(ESMF_State), intent(inout) :: IMPORT
      type(ESMF_State), intent(inout) :: EXPORT
!
! OUTPUT PARAMETERS:
!
      integer, optional, intent(out)  :: RC       ! Error code
!
! !DESCRIPTION:
! Set mass flux and courant exports needed for offline advection. How this
! is done is dependent upon whether importing them via ExtData or computing
! from winds.
!
!EOP
!-------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
      integer :: is, ie, js, je, lm
      integer :: STATUS

      ! Pointers to exports
      real(r8), pointer, dimension(:,:,:) :: MFX_EXPORT => null()
      real(r8), pointer, dimension(:,:,:) :: MFY_EXPORT => null() 
      real(r8), pointer, dimension(:,:,:) :: CX_EXPORT  => null()
      real(r8), pointer, dimension(:,:,:) :: CY_EXPORT  => null()
      real(r8), pointer, dimension(:,:,:) :: SPHU0_EXPORT  => null()

      ! Pointers to imports
      real,     pointer, dimension(:,:,:) :: MFX_IMPORT => null()
      real,     pointer, dimension(:,:,:) :: MFY_IMPORT => null()
      real,     pointer, dimension(:,:,:) :: CX_IMPORT  => null()
      real,     pointer, dimension(:,:,:) :: CY_IMPORT  => null()
      real,     pointer, dimension(:,:,:) :: UA_IMPORT  => null()
      real,     pointer, dimension(:,:,:) :: VA_IMPORT  => null()

      ! Pointer to diagnostic export
      real(r8), pointer, dimension(:,:,:) :: UpwardsMassFlux => null()

      ! Pointers to local arrays
      real,     pointer, dimension(:,:,:) :: UC        => null()
      real,     pointer, dimension(:,:,:) :: VC        => null()
      real(r8), pointer, dimension(:,:,:) :: UCr8      => null()
      real(r8), pointer, dimension(:,:,:) :: VCr8      => null()

      !=====================================
      ! prepare_massflux_exports starts here
      !=====================================

      call lgr%debug('Preparing FV3 input MFX, MFY, CX, and CY')

      is = lbound(PLE, 1); ie = ubound(PLE, 1)
      js = lbound(PLE, 2); je = ubound(PLE, 2)
      lm = size(PLE, 3) - 1

      ! Get exports (real8)
      call MAPL_GetPointer(EXPORT, MFX_EXPORT, 'MFX', RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_GetPointer(EXPORT, MFY_EXPORT, 'MFY', RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_GetPointer(EXPORT, CX_EXPORT, 'CX', RC=STATUS)
      _VERIFY(STATUS)
      call MAPL_GetPointer(EXPORT, CY_EXPORT, 'CY', RC=STATUS)
      _VERIFY(STATUS)

      if ( import_mass_flux_from_extdata ) then

         ! Get SPHU0 export set in prepare_sphu_export
         if ( correct_mass_flux_for_humidity > 0 ) then
            call MAPL_GetPointer(EXPORT, SPHU0_EXPORT, 'SPHU0', RC=STATUS)
            _VERIFY(STATUS)
         endif

         ! Get imports (real4) and copy to exports, converting to real8
         call MAPL_GetPointer(IMPORT, MFX_IMPORT, 'MFXC',  RC=STATUS)
         _VERIFY(STATUS)
         call MAPL_GetPointer(IMPORT, MFY_IMPORT, 'MFYC',  RC=STATUS)
         _VERIFY(STATUS)
         call MAPL_GetPointer(IMPORT, CX_IMPORT, 'CXC',  RC=STATUS)
         _VERIFY(STATUS)
         call MAPL_GetPointer(IMPORT, CY_IMPORT, 'CYC',  RC=STATUS)
         _VERIFY(STATUS)

         if (meteorology_vertical_index_is_top_down) then
            MFX_EXPORT =  dble(MFX_IMPORT(:,:,:))
            MFY_EXPORT =  dble(MFY_IMPORT(:,:,:))
            CX_EXPORT  =  dble(CX_IMPORT(:,:,:))
            CY_EXPORT  =  dble(CY_IMPORT(:,:,:))
         else
            MFX_EXPORT =  dble(MFX_IMPORT(:,:,LM:1:-1))
            MFY_EXPORT =  dble(MFY_IMPORT(:,:,LM:1:-1))
            CX_EXPORT  =  dble(CX_IMPORT(:,:,LM:1:-1))
            CY_EXPORT  =  dble(CY_IMPORT(:,:,LM:1:-1))
         endif

         if ( correct_mass_flux_for_humidity > 0 ) then
            MFX_EXPORT = MFX_EXPORT / ( 1.d0 - SPHU0_EXPORT )
            MFY_EXPORT = MFY_EXPORT / ( 1.d0 - SPHU0_EXPORT )
         endif

      else

         ! Get wind imports (real4, A-grid)
         call MAPL_GetPointer(IMPORT, UA_IMPORT, 'UA', RC=STATUS)
         _VERIFY(STATUS)
         call MAPL_GetPointer(IMPORT, VA_IMPORT, 'VA', RC=STATUS)
         _VERIFY(STATUS)
         
         ! Allocate local arrays for C-grid, both real4 and real8
         ALLOCATE( UC   (is:ie, js:je, lm), STAT=STATUS);
         _VERIFY(STATUS)
         ALLOCATE( VC   (is:ie, js:je, lm), STAT=STATUS);
         _VERIFY(STATUS)
         ALLOCATE( UCr8 (is:ie, js:je, lm), STAT=STATUS);
         _VERIFY(STATUS)
         ALLOCATE( VCr8 (is:ie, js:je, lm), STAT=STATUS);
         _VERIFY(STATUS)
         
         ! Copy imports to local arrays so that vertical index is top down
         if (meteorology_vertical_index_is_top_down) then
            UC(:,:,:) = UA_IMPORT(:,:,:)
            VC(:,:,:) = VA_IMPORT(:,:,:)
         else
            UC(:,:,:) = UA_IMPORT(:,:,LM:1:-1)
            VC(:,:,:) = VA_IMPORT(:,:,LM:1:-1)
         end if
         
         ! Restagger winds (A-grid to C-grid) (requires real4)
         call A2D2C(U=UC, V=VC, npz=lm, getC=.true.)
         
         ! Store as real8 for input to FV3 subroutine to compute mass fluxes
         UCr8  = dble(UC)
         VCr8  = dble(VC)
         
#ifdef ADJOINT
         if (.not. firstRun) THEN
#endif
            ! Calculate mass fluxes and courant numbers
            call fv_computeMassFluxes(UCr8, VCr8, PLE, &
                                      MFX_EXPORT, MFY_EXPORT, & 
                                      CX_EXPORT, CY_EXPORT, dt)
#ifdef ADJOINT
         endif
         firstRun = .false.
#endif
         
         ! Deallocate local arrays
         DEALLOCATE(UC, VC, UCr8, VCr8)

      end if

      ! Set vertical motion diagnostic if enabled in HISTORY.rc
      call MAPL_GetPointer(EXPORT, UpwardsMassFlux, 'UpwardsMassFlux', &
           NotFoundOK=.TRUE., RC=STATUS)
      _VERIFY(STATUS)
      if (associated(UpwardsMassFlux)) then
         call lgr%debug('Calculating diagnostic export UpwardsMassFlux')

         ! Get vertical mass flux
         call fv_getVerticalMassFlux(MFX_EXPORT, MFY_EXPORT, UpwardsMassFlux, dt)

         ! Flip vertical so that GCHP diagnostic is positive="up"
         UpwardsMassFlux(:,:,:) = UpwardsMassFlux(:,:,LM:0:-1)/dt
      end if

      ! nullify pointers
      MFX_EXPORT      => null()
      MFY_EXPORT      => null()
      CX_EXPORT       => null()
      CY_EXPORT       => null()
      SPHU0_EXPORT    => null()
      MFX_IMPORT      => null()
      MFY_IMPORT      => null()
      CX_IMPORT       => null()
      CY_IMPORT       => null()
      UA_IMPORT       => null()
      VA_IMPORT       => null()
      UpwardsMassFlux => null()
      UC              => null()
      VC              => null()
      UCr8            => null()
      VCr8            => null()

      _RETURN(ESMF_SUCCESS)

   end subroutine prepare_massflux_exports
!EOC
!-------------------------------------------------------------------------
!         GEOS-Chem High Performance Global Chemical Transport Model
!-------------------------------------------------------------------------
!BOP
!
! !INTERFACE:
!
   subroutine calculate_ple(PS, PLE, SPHU, topDownMet )
!
! !INPUT PARAMETERS:
!
      real(r4), intent(in)           :: PS(:,:)     ! Surface pressure [hPa]
      real(r4), intent(in), OPTIONAL :: SPHU(:,:,:) ! Specific humidity [kg/kg]
      logical,  intent(in), OPTIONAL :: topDownMet  ! True if meteorology level 1 is TOA
!
! !INPUT PARAMETERS:
!
      real(r8), intent(out)          :: PLE(:,:,:)  ! Edge pressure    [hPa]
!
! !DESCRIPTION:
! Compute edge pressures from surface pressure and grid parameters. This
! subroutine is currently hard-coded for 72 levels only and returns pressure
! with vertical index bottom-up (level 1 is surface) in units of hPa.
!
!EOP
!-------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
      ! NOTE: Want to make number of levels configurable
      integer, parameter  :: num_levels = 72
      integer, parameter  :: num_edges = num_levels + 1
      real(r8)            :: AP(num_edges), BP(num_edges)
      real(r8)            :: PEdge_Bot, PEdge_Top, PSDry
      integer             :: I, J, L, is, ie, js, je, lm

      !================================
      ! calculate_ple starts here
      !================================
      
      AP = 1d0
      BP = 0d0
      
      ! GMAO 72 level grid
      
      ! Ap [hPa] for 72 levels (73 edges)
      AP = (/ 0.000000d+00, 4.804826d-02, 6.593752d+00, 1.313480d+01, &
              1.961311d+01, 2.609201d+01, 3.257081d+01, 3.898201d+01, &
              4.533901d+01, 5.169611d+01, 5.805321d+01, 6.436264d+01, &
              7.062198d+01, 7.883422d+01, 8.909992d+01, 9.936521d+01, &
              1.091817d+02, 1.189586d+02, 1.286959d+02, 1.429100d+02, &
              1.562600d+02, 1.696090d+02, 1.816190d+02, 1.930970d+02, &
              2.032590d+02, 2.121500d+02, 2.187760d+02, 2.238980d+02, &
              2.243630d+02, 2.168650d+02, 2.011920d+02, 1.769300d+02, &
              1.503930d+02, 1.278370d+02, 1.086630d+02, 9.236572d+01, &
              7.851231d+01, 6.660341d+01, 5.638791d+01, 4.764391d+01, &
              4.017541d+01, 3.381001d+01, 2.836781d+01, 2.373041d+01, &
              1.979160d+01, 1.645710d+01, 1.364340d+01, 1.127690d+01, &
              9.292942d+00, 7.619842d+00, 6.216801d+00, 5.046801d+00, &
              4.076571d+00, 3.276431d+00, 2.620211d+00, 2.084970d+00, &
              1.650790d+00, 1.300510d+00, 1.019440d+00, 7.951341d-01, &
              6.167791d-01, 4.758061d-01, 3.650411d-01, 2.785261d-01, &
              2.113490d-01, 1.594950d-01, 1.197030d-01, 8.934502d-02, &
              6.600001d-02, 4.758501d-02, 3.270000d-02, 2.000000d-02, &
              1.000000d-02 /)
      
      ! Bp [unitless] for 72 levels (73 edges)
      BP = (/ 1.000000d+00, 9.849520d-01, 9.634060d-01, 9.418650d-01, &
              9.203870d-01, 8.989080d-01, 8.774290d-01, 8.560180d-01, &
              8.346609d-01, 8.133039d-01, 7.919469d-01, 7.706375d-01, &
              7.493782d-01, 7.211660d-01, 6.858999d-01, 6.506349d-01, &
              6.158184d-01, 5.810415d-01, 5.463042d-01, 4.945902d-01, &
              4.437402d-01, 3.928911d-01, 3.433811d-01, 2.944031d-01, &
              2.467411d-01, 2.003501d-01, 1.562241d-01, 1.136021d-01, &
              6.372006d-02, 2.801004d-02, 6.960025d-03, 8.175413d-09, &
              0.000000d+00, 0.000000d+00, 0.000000d+00, 0.000000d+00, &
              0.000000d+00, 0.000000d+00, 0.000000d+00, 0.000000d+00, &
              0.000000d+00, 0.000000d+00, 0.000000d+00, 0.000000d+00, &
              0.000000d+00, 0.000000d+00, 0.000000d+00, 0.000000d+00, &
              0.000000d+00, 0.000000d+00, 0.000000d+00, 0.000000d+00, &
              0.000000d+00, 0.000000d+00, 0.000000d+00, 0.000000d+00, &
              0.000000d+00, 0.000000d+00, 0.000000d+00, 0.000000d+00, &
              0.000000d+00, 0.000000d+00, 0.000000d+00, 0.000000d+00, &
              0.000000d+00, 0.000000d+00, 0.000000d+00, 0.000000d+00, &
              0.000000d+00, 0.000000d+00, 0.000000d+00, 0.000000d+00, &
              0.000000d+00 /)

      
      ! Calculate bottom-up level edge pressures [hPa]
      if ( .not. PRESENT( SPHU ) ) then

         ! Total pressure
         do L=1,num_edges
            PLE(:,:,L) = AP(L) + ( BP(L) * dble(PS(:,:)) )
         enddo

      else

         ! Dry pressure
         is = lbound(PS,1)
         ie = ubound(PS,1)
         js = lbound(PS,2)
         je = ubound(PS,2)
         LM = size  (SPHU,3)

         if ( topDownMet ) then

           do J=js,je
           do I=is,ie

              ! Start with TOA pressure
              PSDry = AP(LM+1)

              ! Stack up dry delta-P to get surface dry pressure
              ! Vertically flip humidity if using top-down meteorology (raw GMAO files)
              do L=1,LM
                 PEdge_Bot = AP(L  ) + ( BP(L  ) * dble(PS(I,J)) )
                 PEdge_Top = AP(L+1) + ( BP(L+1) * dble(PS(I,J)) )
                 PSDry = PSDry &
                         + ( ( PEdge_Bot - Pedge_Top ) * ( 1.d0 - SPHU(I,J,LM-L+1) ) )
              enddo

              ! Work back up from the surface to get dry level edges
              do L=1,LM+1
                 PLE(I,J,L) = AP(L) + ( BP(L) * dble(PSDry) )
              enddo

           enddo
           enddo

         else

            do J=js,je
            do I=is,ie

               ! Start with TOA pressure
               PSDry = AP(LM+1)

               ! Stack up dry delta-P to get surface dry pressure
               do L=1,LM
                  PEdge_Bot = AP(L  ) + ( BP(L  ) * dble(PS(I,J)) )
                  PEdge_Top = AP(L+1) + ( BP(L+1) * dble(PS(I,J)) )
                  PSDry = PSDry &
                          + ( ( PEdge_Bot - Pedge_Top ) * ( 1.d0 - SPHU(I,J,L) ) )
               enddo

               ! Work back up from the surface to get dry level edges
               do L=1,LM+1
                  PLE(I,J,L) = AP(L) + ( BP(L) * dble(PSDry) )
               enddo
            enddo
            enddo

         endif

      endif


   end subroutine calculate_ple
!EOC
   
end module GCHPctmEnv_GridComp
