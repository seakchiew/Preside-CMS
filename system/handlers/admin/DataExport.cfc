component extends="preside.system.base.adminHandler" {
	property name="presideObjectService" inject="PresideObjectService";
	property name="loginService"         inject="LoginService";

	public void function prehandler( event, rc, prc, args={} ) {
		super.preHandler( argumentCollection=arguments );

		if ( !isEmpty( rc.object ?: "" ) ) {
			var i18nBase = presideObjectService.getResourceBundleUriRoot( rc.object );

			event.addAdminBreadCrumb(
				  title = translateResource( uri=i18nBase & "title.singular" )
				, link  = event.buildAdminLink( objectName=rc.object )
			);
		} else {
			event.notFound();
		}
	}

	public void function saveExport( event, rc, prc, args={} ) {
		event.addAdminBreadCrumb(
			  title = translateResource( uri="cms:savedexport.saveexport.title" )
			, link  = event.buildAdminLink( linkto="dataExport.saveExport", persistStruct=rc )
		);

		prc.pageIcon  = "save";
		prc.pageTitle = translateResource( uri="cms:savedexport.saveexport.title" );

		if ( !isEmpty( rc.object ?: "" ) ) {
			var i18nBase = presideObjectService.getResourceBundleUriRoot( rc.object );
			prc.pageSubtitle = translateResource( uri="cms:savedexport.saveexport.subtitle",  data=[ translateResource( uri=i18nBase & "title.singular", defaultValue="" ) ] );

			if ( !Len( Trim( rc.filename ?: "" ) ) ) {
				rc.filename = slugify( translateResource( uri=i18nBase & "title", defaultValue="" ) );
			}

			rc.filterObject = rc.object;
		}
	}

	public void function saveExportAction( event, rc, prc, args={} ) {
		var formData         = event.getCollectionForForm();
		var validationResult = validateForms();

		if ( !validationResult.validated() ) {
			messageBox.error( translateResource( uri="cms:datamanager.saveexport.error" ) );
			setNextEvent( url=event.buildAdminLink( linkto="dataExport.saveExport" ), persistStruct=formData );
		}

		var newSavedExportId = "";
		var data             =  {
			  label         = formData.label              ?: ""
			, description   = formData.description        ?: ""
			, file_name     = formData.filename           ?: ""
			, object_name   = formData.object             ?: ""
			, filter_string = formData.exportFilterString ?: ""
			, fields        = formData.exportFields       ?: ""
			, exporter      = formData.exporter           ?: ""
			, order_by      = formData.orderBy            ?: ""
			, search_query  = formData.searchQuery        ?: ""
			, created_by    = loginService.getLoggedInUserId()
			, recipients    = formData.recipients         ?: ""
			, schedule      = formData.schedule           ?: "disabled"
		};

		if ( isFeatureEnabled( "rulesEngine" ) ) {
			data.filter       = formData.filterExpressions ?: "";
			data.saved_filter = formData.savedFilters      ?: "";
		}

		try {
			newSavedExportId = presideObjectService.insertData(
				  objectName              = "saved_export"
				, data                    = data
				, insertManyToManyRecords = true
			);
		} catch ( any e ) {
			logError( e );
		}

		if( !isEmpty( newSavedExportId ) ) {
			messageBox.info( translateResource( uri="cms:datamanager.saveexport.confirmation" ) );
			setNextEvent( url=event.buildAdminLink( objectName="saved_export", operation="listing", queryString="object_name=#formData.object#" ) );
		} else {
			messageBox.error( translateResource( uri="cms:datamanager.saveexport.error" ) );
			setNextEvent( url=event.buildAdminLink( objectName=formData.object, operation="listing" ) );
		}
	}
}