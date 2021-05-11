component {
	property name="assetManagerService"        inject="assetManagerService";
	property name="formBuilderStorageProvider" inject="formBuilderStorageProvider";
	property name="storageProviderService"     inject="storageProviderService";

	private any function renderResponse( event, rc, prc, args={} ) {
		var fileName = ReReplace( args.response ?: "", "^""(.*?)""$", "\1" );

		if ( Len( Trim( fileName ) ) && fileName != "{}" ) {
			var downloadLink = event.buildLink(
				  fileStorageProvider = 'formBuilderStorageProvider'
				, fileStoragePath     = fileName
			);

			return '<a target="_blank" href="#downloadLink#"><i class="fa fa-fw fa-download blue"></i> #Trim( fileName )#</a>';
		}

		return translateResource( "formbuilder.item-types.fileupload:render.empty.response" );
	}


	private array function renderResponseForExport( event, rc, prc, args={} ) {
		var fileName = Listlast( args.response ?: "", '/\' );

		if ( Len( Trim( fileName ) ) && fileName != "{}" ) {
			return [ event.buildLink(
				  fileStorageProvider = 'formBuilderStorageProvider'
				, fileStoragePath     = args.response
			) ];
		}

		return [ translateResource( "formbuilder.item-types.fileupload:render.empty.response" ) ];
	}

	private string function renderInput( event, rc, prc, args={} ) {
		var accept = "";

		if ( Len( Trim( args.accept ?: "" ) ) ) {
			assetManagerService.expandTypeList( ListToArray( args.accept ) ).each( function( type ){
				accept = ListAppend( accept, ".#type#" );
			} );
		}

		return renderFormControl(
			  argumentCollection = args
			, type               = "fileupload"
			, context            = "formbuilder"
			, id                 = args.id ?: ( args.name ?: "" )
			, layout             = ""
			, required           = IsTrue( args.mandatory ?: "" )
			, accept             = accept
			, maximumFileSize    = Val( args.maximumFileSize ?: 0 )
		);
	}

	private array function getValidationRules( event, rc, prc, args={} ) {
		var rules = [];

		if ( Val( args.maximumFileSize ?: "" ) ) {
			rules.append( {
				  fieldname = args.name ?: ""
				, validator = "fileSize"
				, params    = { maxSize = args.maximumFileSize }
			} );
		}

		if( Len( Trim( args.accept ?: "" ) ) ){
			var allowedTypes = ArrayToList( assetManagerService.expandTypeList( listToArray(args.accept) ) );
			rules.append( {
				  fieldname = args.name ?: ""
				, validator = "fileType"
				, params    = { allowedTypes=allowedTypes, allowedExtensions=allowedTypes }
			} );
		}

		return rules;
	}

	private any function getItemDataFromRequest( event, rc, prc, args={} ) {
		var tmpFileDetails = runEvent(
			  event          = "preprocessors.fileupload.index"
			, prePostExempt  = true
			, private        = true
			, eventArguments = { fieldName=args.inputName ?: "", preProcessorArgs={}, readBinary=false }
		);

		return tmpFileDetails;
	}

	private any function renderResponseToPersist( event, rc, prc, args={} ) {
		var response = args.response ?: "";

		if ( FileExists( response.path ?: "" ) ) {
			var savedPath = "/#( args.formId ?: '' )#/#CreateUUId()#/#( Len( response.tempFileInfo.clientFile ?: '' ) ? urlEncode( response.tempFileInfo.clientFile ) : 'uploaded.file' )#";

			if ( storageProviderService.providerSupportsFileSystem( formBuilderStorageProvider ) ) {
				formBuilderStorageProvider.putObjectFromLocalPath(
					  localPath = response.path
					, path      = savedPath
				);
			} else {
				formBuilderStorageProvider.putObject(
					  object = FileReadBinary( response.path )
					, path   = savedPath
				);
			}

			return savedPath;
		}

		return SerializeJson( response );
	}

	private string function renderV2ResponsesForDb( event, rc, prc, args={} ) {
		return renderResponseToPersist( argumentCollection=arguments );
	}

	private string function getQuestionDataType( event, rc, prc, args={} ) {
		return "text";
	}
}