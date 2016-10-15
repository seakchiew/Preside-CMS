/**
 * This service exists to provide APIs that make providing support for multilingual
 * translations of standard preside objects possible in a transparent way. Note: You are
 * unlikely to need to deal with this API directly.
 *
 * @autodoc
 * @singleton
 * @presideService
 */
component displayName="Multilingual Preside Object Service" {

// CONSTRUCTOR
	/**
	 * @relationshipGuidance.inject relationshipGuidance
	 * @cookieService.inject        cookieService
	 */
	public any function init( required any relationshipGuidance, required any cookieService ) {
		_setRelationshipGuidance( arguments.relationshipGuidance );
		_setCookieService( arguments.cookieService );
		_setMultiLingualObjectReference( {} );

		return this;
	}

// PUBLIC METHODS

	/**
	 * Returns whether or not the given object and optional property are multilingual
	 * enabled.
	 *
	 * @autodoc           true
	 * @objectName.hint   Name of the object that we wish to check
	 * @propertyName.hint Optional name of the property that we wish to check
	 */
	public boolean function isMultilingual( required string objectName, string propertyName="" ) {
		var multiLingualObjectReference = _getMultiLingualObjectReference();

		if ( !multiLingualObjectReference.keyExists( arguments.objectName ) ) {
			return false;
		}

		return !Len( Trim( arguments.propertyName ) ) || multiLingualObjectReference[ arguments.objectName ].findNoCase( arguments.propertyName );
	}

	/**
	 * Performs the magic of creating extra database tables (preside objects) to store the
	 * translations of multilingual enabled objects.
	 *
	 * @autodoc      true
	 * @objects.hint Objects as compiled and read by the preside object service.
	 */
	public void function addTranslationObjectsForMultilingualEnabledObjects( required struct objects ) {
		var multiLingualObjectReference = {};

		for( var objectName in arguments.objects ){
			var object = arguments.objects[ objectName ];

			if ( _isObjectMultilingual( object.meta ?: {} ) ) {

				arguments.objects[ _getTranslationObjectPrefix() & objectName ] = createTranslationObject( objectName, object );
				decorateMultilingualObject( objectName, object );
				multiLingualObjectReference[ objectName ] = _listMultilingualObjectProperties( object.meta );
			}
		}

		_setMultiLingualObjectReference( multiLingualObjectReference );
	}

	/**
	 * Returns the meta data for our auto generated translation object based on a given
	 * source object
	 *
	 * @autodoc           true
	 * @objectName.hint   The name of the source object
	 * @sourceObject.hint The metadata of the source object
	 */
	public struct function createTranslationObject( required string objectName, required struct sourceObject ) {
		var translationObject     = Duplicate( arguments.sourceObject.meta );
		var translationProperties = translationObject.properties ?: {};
		var dbFieldList           = ListToArray( translationObject.dbFieldList ?: "" );
		var propertyNames         = translationObject.propertyNames ?: [];
		var validProperties       = _listMultilingualObjectProperties( arguments.sourceObject.meta ?: {} );
		var extraLanguageIndexes  = "";

		validProperties.append( "id" );
		validProperties.append( "datecreated" );
		validProperties.append( "datemodified" );

		translationObject.tableName    = _getTranslationObjectPrefix() & ( arguments.sourceObject.meta.tableName ?: "" );
		translationObject.derivedFrom  = arguments.objectName;
		translationObject.siteFiltered = false;
		translationObject.isPageType   = false;

		for( var propertyName in translationProperties ) {
			if ( !validProperties.find( propertyName ) ) {
				translationProperties.delete( propertyName );
				dbFieldList.delete( propertyName );
				propertyNames.delete( propertyName );
				continue;
			}

			var prop = translationProperties[ propertyName ];

			if ( Len( Trim( prop.uniqueindexes ?: "" ) ) ) {
				var newIndexDefinition = "";

				for( var ix in ListToArray( prop.uniqueindexes ) ) {
					var languageIndexName = ListFirst( ix, "|" ) & "|1";

					if ( !ListFindNoCase( extraLanguageIndexes, languageIndexName ) ) {
						extraLanguageIndexes = ListAppend( extraLanguageIndexes, languageIndexName );
					}

					if ( ListLen( ix, "|" ) > 1 ) {
						newIndexDefinition = ListAppend( newIndexDefinition, ListFirst( ix, "|" ) & "|" & Val( ListRest( ix, "|" ) )+1 );
					} else {
						newIndexDefinition = ListAppend( newIndexDefinition, ix & "|2" );
					}
				}

				prop.uniqueindexes = newIndexDefinition;
			}
		}
		if ( Len( Trim( extraLanguageIndexes ) ) ) {
			extraLanguageIndexes = "," & extraLanguageIndexes;
		}

		translationProperties._translation_source_record = {
			  name          = "_translation_source_record"
			, relationship  = "many-to-one"
			, relatedto     = arguments.objectName
			, required      = true
			, uniqueindexes = "translation|1"
			, indexes       = ""
			, ondelete      = "cascade"
			, onupdate      = "cascade"
			, generator     = "none"
			, control       = "none"
		};
		dbFieldList.append( "_translation_source_record" );
		propertyNames.append( "_translation_source_record" );

		translationProperties._translation_language = {
			  name          = "_translation_language"
			, relationship  = "many-to-one"
			, relatedto     = "multilingual_language"
			, required      = true
			, uniqueindexes = "translation|2" & extraLanguageIndexes
			, indexes       = ""
			, ondelete      = "error"
			, onupdate      = "cascade"
			, generator     = "none"
			, control       = "none"
		};
		dbFieldList.append( "_translation_language" );
		propertyNames.append( "_translation_language" );

		translationObject.dbFieldList   = dbFieldList.toList();
		translationObject.propertyNames = propertyNames;

		translationObject.indexes       = translationObject.indexes ?: {};
		for( var indexName in translationObject.indexes ) {
			for( var indexField in translationObject.indexes[ indexName ].fields.listToArray() ) {
				if ( !dbFieldList.findNoCase( indexField ) ) {
					translationObject.indexes.delete( indexName );
					break;
				}
			}

			if ( translationObject.indexes.keyExists( indexName ) && translationObject.indexes[ indexName ].unique ) {
				translationObject.indexes[ indexName ].fields = "_translation_language," & translationObject.indexes[ indexName ].fields;
			}
		}
		translationObject.indexes[ "ux_translation_" & arguments.objectName & "_translation" ] = { unique=true, fields="_translation_source_record,_translation_language" };

		return { meta=translationObject, instance="auto_created" };
	}

	/**
	 * Adds utility properties to the multilingual enabled source object
	 * so that its translations can be easily queried
	 *
	 * @autodoc         true
	 * @objectName.hint The name of the source object
	 * @object.hint     The metadata of the source object
	 */
	public void function decorateMultilingualObject( required string objectName, required struct object ) {
		arguments.object.meta.properties = arguments.object.meta.properties ?: {};

		arguments.object.meta.properties._translations = {
			  name            = "_translations"
			, relationship    = "one-to-many"
			, relatedto       = _getTranslationObjectPrefix() & arguments.objectName
			, relationshipKey = "_translation_source_record"
			, required        = false
			, uniqueindexes   = ""
			, indexes         = ""
			, generator       = "none"
			, control         = "none"
		};
	}

	/**
	 * Works on intercepted select queries to discover and replace multilingual
	 * select fields with special IfNull( translation, original ) syntax
	 * to automagically select translations without the developer having to
	 * do anything about it
	 *
	 * @autodoc           true
	 * @objectName.hint   The name of the source object
	 * @selectFields.hint Array of select fields as passed into the presideObjectService.selectData() method
	 * @adapter.hint      Database adapter to be used in generating the select query SQL
	 */
	public void function mixinTranslationSpecificSelectLogicToSelectDataCall( required string objectName, required array selectFields, required any adapter ) {
		for( var i=1; i <= arguments.selectFields.len(); i++ ) {
			var field = arguments.selectFields[ i ];
			var resolved = _resolveSelectField( arguments.objectName, field );

			if ( !resolved.isEmpty() && isMultilingual( resolved.objectName, resolved.propertyName ) ) {
				arguments.selectFields[ i ] = _transformSelectFieldToGetTranslationIfExists( arguments.objectName, resolved.selector, resolved.alias, arguments.adapter );
			}
		}
	}

	/**
	 * Works on intercepted select queries to discover and decorate
	 * joins on translation objects with an additional clause for the
	 * passed in language
	 *
	 * @autodoc             true
	 * @tableJoins.hint     Array of table joins as calculated by the SelectData() logic
	 * @joins.hint          Array of raw joins as calculated by the SelectData() logic that match the table joins
	 * @language.hint       The language to filter on
	 * @preparedFilter.hint The fully prepared and resolved filter that will be used in the select query
	 */
	public void function addLanguageClauseToTranslationJoins( required array tableJoins, required string language, required struct preparedFilter, boolean fromVersionTable=false ) {
		for( var i=1; i <= arguments.tableJoins.len(); i++ ){
			if ( ListLast( arguments.tableJoins[ i ].tableAlias, "$" ) == "_translations" ) {

				if ( arguments.tableJoins[ i ].keyExists( "additionalClauses" ) ) {
					arguments.tableJoins[ i ].additionalClauses &= " and #arguments.tableJoins[ i ].tableAlias#._translation_language = :_translation_language";
				} else {
					arguments.tableJoins[ i ].additionalClauses = "#arguments.tableJoins[ i ].tableAlias#._translation_language = :_translation_language";
				}

				if ( !$getRequestContext().showNonLiveContent() ) {
					var joinTarget = arguments.joins[ i ].joinToObject ?: "";
					if ( joinTarget.len() && $getPresideObjectService().objectIsVersioned( joinTarget ) ) {
						arguments.tableJoins[ i ].additionalClauses &= " and ( #arguments.tableJoins[ i ].tableAlias#._version_is_draft is null or #arguments.tableJoins[ i ].tableAlias#._version_is_draft = '0' )";
					}
				}

				arguments.tableJoins[ i ].type = "left";

				arguments.preparedFilter.params.append( { name="_translation_language", type="varchar", value=arguments.language } );

				if ( arguments.fromVersionTable ) {
					arguments.tableJoins[ i ].tableName = "_version_" & arguments.tableJoins[ i ].tableName;
				}
			}
		}
	}

	/**
	 * Works on intercepted select queries to add versioning clauses to translation
	 * table joins
	 *
	 * @autodoc
	 *
	 */
	public void function addVersioningClausesToTranslationJoins( required struct selectDataArgs ) {

		if ( !selectDataArgs.specificVersion ) {
			var poService          = $getPresideObjectService();
			var versionedObject    = selectDataArgs.objectName;

			if ( !isMultilingual( selectDataArgs.objectName ) ) {
				if ( poService.isPageType( selectDataArgs.objectName ) ) {
					versionedObject = "page";
				} else {
					return;
				}
			}

			var versionObjectName  = poService.getVersionObjectName( getTranslationObjectName( versionedObject ) );
			var tableName          = poService.getObjectAttribute( versionObjectName, "tablename", "" );


			for( var i=selectDataArgs.joins.len(); i>0; i-- ) {
				var join             = selectDataArgs.joins[i];
				var latestCheckField = IsBoolean( selectDataArgs.allowDraftVersions ?: "" ) && selectDataArgs.allowDraftVersions ? "_version_is_latest_draft" : "_version_is_latest";

				if ( join.tableAlias contains "_translations" && join.tableName.startsWith( "_version" ) ) {
					join.additionalClauses &= " and #join.tableAlias#.#latestCheckField# = 1";
				}
			}
		}
	}

	/**
	 * Returns an array of actively supported languages. Each language
	 * is represented as a struct with id, name, native_name, iso_code and default keys
	 *
	 * @includeDefault.hint Whether or not to include the default language in the array
	 * @autoDoc             true
	 */
	public array function listLanguages( boolean includeDefault=true ) {
		var settings        = $getPresideCategorySettings( "multilingual" );
		var defaultLanguage = settings.default_language ?: "";
		var languageIds     = ListToArray( settings.additional_languages ?: "" );
		var languages       = [];

		if ( arguments.includeDefault && defaultLanguage.len() ) {
			languageIds.prepend( defaultLanguage );
		}

		var dbRecords = _getLanguageDao().selectData( filter={ id=languageIds } );

		for( var record in dbRecords ) {
			record.default = record.id == defaultLanguage;
			record.sortOrder = languageIds.find( record.id );
			languages.append( record );
		}

		languages.sort( function( a, b ){
			return a.sortorder > b.sortorder ? 1 : -1;
		} );

		return languages;
	}

	/**
	 * Returns an array of actively supported languages as per listLanguages()
	 * with an additional 'status' field indicating the status of the translation
	 * for the given object record
	 *
	 * @objectName.hint Name of the object that has the record we wish to get the translation status of
	 * @recordId.hint   ID of the record we wish to get the translation status of
	 * @autoDoc         true
	 */
	public array function getTranslationStatus( required string objectName, required string recordId ) {
		var languages         = listLanguages( includeDefault=false );
		var objectIsVersioned = $getPresideObjectService().objectIsVersioned( arguments.objectName );
		var selectFields      = objectIsVersioned ? [ "_translation_language", "_version_is_draft", "_version_has_drafts" ] : [ "_translation_language" ];
		var dbRecords         = $getPresideObjectService().selectData(
			  objectName         = _getTranslationObjectPrefix() & objectName
			, selectFields       = selectFields
			, filter             = { _translation_source_record = arguments.recordId }
			, allowDraftVersions = true
		);
		var mappedRecords = {};

		for( var record in dbRecords ){
			if ( objectIsVersioned ) {
				mappedrecords[ record._translation_language ] = ( !IsBoolean( record._version_is_draft ) || !record._version_is_draft ) && ( !IsBoolean( record._version_has_drafts ) || !record._version_has_drafts );
			} else {
				mappedrecords[ record._translation_language ] = true;
			}
		}

		for( var language in languages ) {
			if ( mappedRecords.keyExists( language.id ) ) {
				language.status = mappedRecords[ language.id ] ? "active" : "inprogress";
			} else {
				language.status = "notstarted"
			}
		}

		return languages;
	}

	/**
	 * Returns a structure of language details for the given language.
	 * If the language is not an actively translatable language,
	 * an empty structure will be returned.
	 *
	 * @languageId.hint ID of the language to get
	 * @autodoc         true
	 *
	 */
	public struct function getLanguage( required string languageId ) {
		var languages = listLanguages();
		for( var language in languages ) {
			if ( language.id == arguments.languageId ) {
				return language;
			}
		}

		return {};
	}

	/**
	 * Returns the name of the given object's corresponding translation object
	 *
	 * @objectName.hint Name of the object who's corresponding translation object name we wish to get
	 * @autodoc         true
	 *
	 */
	public string function getTranslationObjectName( required string sourceObjectName ) {
		return _getTranslationObjectPrefix() & arguments.sourceObjectName;
	}

	/**
	 * Returns the equivalent translation record
	 * for the given object record (object name and id)
	 * and language
	 *
	 * @autodoc
	 *
	 */
	public query function selectTranslation( required string objectName, required string id, required string languageId, array selectFields=[], string version="", boolean useCache=true ) {
		var translationObjectName = getTranslationObjectName( arguments.objectName );
		var filter                = { _translation_source_record=arguments.id, _translation_language=arguments.languageId };
		var presideObjectService  = $getPresideObjectService();
		var args                  = {
			  objectName         = translationObjectName
			, filter             = filter
			, selectFields       = arguments.selectFields
			, allowDraftVersions = true
		};

		if ( !arguments.useCache ) {
			args.useCache = false;
		}

		if ( Val( arguments.version ) ) {
			args.fromVersionTable = true;
			args.specificVersion  = arguments.version;
		}

		return presideObjectService.selectData( argumentCollection=args );
	}

	/**
	 * Saves a translation record for a given preside object
	 * and record ID
	 *
	 * @autodoc
	 * @objectName.hint Name of the object who's record we are to save the translation for
	 * @id.hint         ID of the record we are to save the translation for
	 * @languageId.hint ID of the language that the translation is for
	 * @data.hint       Structure of data containing to save in the translation record
	 *
	 */
	public string function saveTranslation(
 		  required string  objectName
		, required string  id
		, required string  languageId
		, required struct  data
		,          boolean isDraft = false
	){
		var returnValue = "";

		transaction {
			var translationObjectName = getTranslationObjectName( arguments.objectName );
			var existingId            = getExistingTranslationId( argumentCollection=arguments );

			if ( existingId.len() ) {
				returnValue = existingId;
				$getPresideObjectService().updateData(
					  objectName              = translationObjectName
					, id                      = existingId
					, data                    = arguments.data
					, updateManyToManyRecords = true
					, isDraft                 = arguments.isDraft
				);
			} else {
				var newRecordData = Duplicate( arguments.data );
				    newRecordData._translation_source_record = arguments.id;
				    newRecordData._translation_language      = arguments.languageId;

				returnValue = $getPresideObjectService().insertData(
					  objectName              = translationObjectName
					, data                    = newRecordData
					, insertManyToManyRecords = true
					, isDraft                 = arguments.isDraft
				);
			}
		}

		return returnValue;
	}

	public string function getExistingTranslationId(
		  required string objectName
		, required string id
		, required string languageId
	) {
		var existing = selectTranslation(
			  objectName   = arguments.objectName
			, id           = arguments.id
			, languageId   = arguments.languageId
			, selectFields = [ "id" ]
		);

		return existing.id ?: "";
	}

	/**
	 * Returns a query record for the detected language
	 * for this request.
	 *
	 * @autodoc
	 * @localeSlug.hint locale detected in URL
	 *
	 */
	public query function getDetectedRequestLanguage( required string localeSlug ) {
		var languageObj  = $getPresideObject( "multilingual_language" );
		var validateLang = function( required query lang ){
			var multilingualSettings = $getPresideCategorySettings( "multilingual" );
			var configuredLanguages  = ListToArray( ListAppend( multilingualSettings.additional_languages ?: "", multilingualSettings.default_language ?: "" ) );

			return configuredLanguages.findNoCase( lang.id ) ? lang : QueryNew( 'id,slug' );
		}

		if ( Len( Trim( arguments.localeSlug ) ) ) {
			var languageFromSlug = languageObj.selectData( filter={ slug=arguments.localeSlug } );

			if ( languageFromSlug.recordCount ) {
				return validateLang( languageFromSlug );
			}
		}

		var languageFromCookie = _getCookieService().getVar( "_preside_language", "" );
		if ( Len( Trim( languageFromCookie ) ) ) {
			languageFromCookie = languageObj.selectData( id=languageFromCookie );
			if ( languageFromCookie.recordCount ) {
				return validateLang( languageFromCookie );
			}
		}

		var languageFromAcceptHeader = ListToArray( cgi.http_accept_language ?: "", ";" );
		if ( languageFromAcceptHeader.len() ) {
			for( var isoCode in languageFromAcceptHeader ) {
				if ( !isNumeric( isoCode ) ) {
					var languageFromIsoCode = languageObj.selectData( filter={ iso_code = isoCode } );
					if ( languageFromIsoCode.recordCount ) {
						return validateLang( languageFromIsoCode );
					}
				}
			}
		}

		var defaultLanguage = $getPresideSetting( "multilingual", "default_language" );
		if ( defaultLanguage.len() ) {
			return validateLang( languageObj.selectData( id=defaultLanguage ) );
		}

		return QueryNew('id,slug');
	}

	/**
	 * Persists the user's language choice so that it can be used
	 * as the default language when it is unclear from the request
	 * what language to use.
	 *
	 * @autodoc
	 * @languageId.hint The ID of the language to persist
	 *
	 */
	public void function persistUserLanguage( required string languageId ) {
		_getCookieService().setVar( name="_preside_language", value=arguments.languageId );
	}

// PRIVATE HELPERS
	private boolean function _isObjectMultilingual( required struct objectMeta ) {
		var multilingualFlag = arguments.objectMeta.multilingual ?: "";

		return IsBoolean( multilingualFlag ) && multilingualFlag;
	}

	private array function _listMultilingualObjectProperties( required struct objectMeta ) {
		var multilingualProperties = [];
		var objectProperties       = arguments.objectMeta.properties ?: {};

		for( var propertyName in objectProperties ) {
			var property = objectProperties[ propertyName ];
			if ( IsBoolean( property.multilingual ?: "" ) && property.multilingual ) {
				multilingualProperties.append( propertyName );
			}
		}

		return multilingualProperties;
	}

	private struct function _resolveSelectField( required string sourceObject, required string selectField ) {
		var fieldMinusSqlEscapes = ReReplace( arguments.selectField, "[`\[\]]", "", "all" );
		var bareFieldRegex       = "^[_a-zA-Z][_a-zA-Z0-9\$]*$";

		if ( ReFind( bareFieldRegex, fieldMinusSqlEscapes ) ) {
			return {
				  objectName   = arguments.sourceObject
				, propertyName = fieldMinusSqlEscapes
				, selector     = "#arguments.sourceObject#.#fieldMinusSqlEscapes#"
				, alias        = fieldMinusSqlEscapes
			};
		}


		var fieldRegex       = "^[_a-zA-Z][_a-zA-Z0-9\$]*\.[_a-zA-Z][_a-zA-Z0-9]*$";
		var selectFieldParts = ListToArray( fieldMinusSqlEscapes, " " );

		if ( !selectFieldParts.len() || !ReFind( fieldRegex, selectFieldParts[ 1 ] ) || selectFieldParts.len() > 3 || ( selectFieldParts.len() == 3 && selectFieldParts[ 2 ] != "as" ) ) {
			return {};
		}

		var selector     = selectFieldParts[ 1 ];
		var propertyName = ListLast( selector, "." );
		var objectPath   = ListFirst( selector, "." );
		var objectName   = _getRelationshipGuidance().resolveRelationshipPathToTargetObject( arguments.sourceObject, objectPath );


		if ( !objectName.len() ) {
			return {};
		}

		return {
			  objectName   = objectName
			, propertyName = propertyName
			, selector     = selector
			, alias        = selectFieldParts.len() == 1 ? propertyName : selectFieldParts[ selectFieldParts.len() ]
		}
	}

	private string function _transformSelectFieldToGetTranslationIfExists( required string objectName, required string selector, required string alias, required any dbAdapter ) {
		var translationsObjectSelector = _getTranslatedObjectRelationshipPath( arguments.objectName, ListFirst( arguments.selector, "." ) );
		var translationSelector        = translationsObjectSelector & "." & ListRest( arguments.selector, "." );

		return dbAdapter.getIfNullStatement( translationSelector, arguments.selector, arguments.alias );
	}

	private string function _getTranslatedObjectRelationshipPath( required string objectName, required string plainObjectPath ) {
		if ( arguments.plainObjectPath == arguments.objectName ) {
			return "_translations";
		}

		return arguments.plainObjectPath & "$_translations";
	}

	private string function _getTranslationObjectPrefix() {
		return "_translation_";
	}

	private any function _getLanguageDao() {
		return $getPresideObject( "multilingual_language" );
	}

// GETTERS AND SETTERS
	private struct function _getMultiLingualObjectReference() {
		return _multiLingualObjectReference;
	}
	private void function _setMultiLingualObjectReference( required struct multiLingualObjectReference ) {
		_multiLingualObjectReference = arguments.multiLingualObjectReference;
	}

	private any function _getRelationshipGuidance() {
		return _relationshipGuidance;
	}
	private void function _setRelationshipGuidance( required any relationshipGuidance ) {
		_relationshipGuidance = arguments.relationshipGuidance;
	}

	private any function _getCookieService() {
		return _cookieService;
	}
	private void function _setCookieService( required any cookieService ) {
		_cookieService = arguments.cookieService;
	}
}