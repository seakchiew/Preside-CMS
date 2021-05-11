/**
 * @singleton      true
 * @presideService true
 */
component {
	/**
	 * @threadUtil.inject    threadUtil
	 */
	public any function init(
		  required any threadUtil
	) {
		_setThreadUtil( arguments.threadUtil );

		_setMachineId();
		_setRunningExports({});

		return this;
	}

	public string function getHistoryExportFile( required string historyExportId ) {
		var file = $getPresideObject( "saved_export_history" ).selectData( id=arguments.historyExportId, selectFields=[ "filepath" ] );

		if ( file.recordcount ) {
			return file.filepath ?: "";
		}

		return "";
	}

	public void function saveFilePathToHistoryExport( required string filepath, required string historyExportId ) {
		try {
			$getPresideObject( "saved_export_history" ).updateData( id=arguments.historyExportId, data={ filepath=arguments.filepath } );
		} catch (any e) {
			$raiseError(e);
		}
	}

	public void function sendExportedFileToRecipient( required string historyExportId ) {
		try {
			var detail          = getHistoryExportDetail( arguments.historyExportId );
			var scheduledExport = detail.saved_export ?: "";
			var exportFilepath  = detail.filepath     ?: ""

			if ( !isEmpty( scheduledExport ) and !isEmpty( exportFilepath ) ) {
				var recipients = valueArray( $getPresideObject( "saved_export" ).selectManyToManyData(
					  id           = scheduledExport
					, propertyName = "recipients"
					, selectFields = [ "recipients.id" ]
				), "id" ) ?: [];

				for ( var recipient in recipients ) {
					$sendEmail(
						  template    = "scheduledExport"
						, recipientId = recipient
						, args        = {
							  filepath        = exportFilepath
							, savedExportName = $renderLabel( "saved_export", scheduledExport )
						}
					);
				}
			}
		} catch (any e) {
			$raiseError(e);
		}
	}

	public struct function getExportDetail( required string exportId ) {
		var detail = $getPresideObject( "saved_export" ).selectData( id=arguments.exportId );

		return !isEmpty( detail ) ? queryGetRow( detail, 1 ) : {};
	}

	public query function getSavedExportHistory( required string exportId ) {
		return $getPresideObject( "saved_export_history" ).selectData( filter={ saved_export=arguments.exportId } );
	}

	public boolean function objectHasSavedExport( required string objectName ) {
		return $getPresideObject( "saved_export" ).dataExists( filter={ object_name=arguments.objectName } );
	}

	public struct function getHistoryExportDetail( required string historyExportId ) {
		var detail = $getPresideObject( "saved_export_history" ).selectData( id=arguments.historyExportId );

		return !isEmpty( detail ) ? queryGetRow( detail, 1 ) : {};
	}

	public void function updateScheduleExport( required string recordId ) {
		try {
			var detail = getExportDetail( arguments.recordId );

			if ( !isEmpty( detail ) and !isEmpty( detail.schedule ?: "" ) ) {
				$getPresideObject( "saved_export" ).updateData( id=arguments.recordId, data={ next_run=getNextRunDate( detail.schedule ) } );
			}
		} catch (any e) {
			$raiseError( e );
		}
	}

	public string function getNextRunDate( required string schedule, date lastRun=now() ) {
		if ( !Len( Trim( arguments.schedule ) ) || arguments.schedule == "disabled" ) {
			return "";
		}

		var cronTabExpression = _getCrontabExpressionObject( arguments.schedule );
		var lastRunJodaTime   = _createJodaTimeObject( arguments.lastRun );

		return cronTabExpression.nextTimeAfter( lastRunJodaTime  ).toDate();
	}

	public string function cronExpressionToHuman( required string expression ) {
		if ( arguments.expression == "disabled" ) {
			return "Disabled";
		}
		return CreateObject( "java", "net.redhogs.cronparser.CronExpressionDescriptor", _getLib() ).getDescription( arguments.expression );
	}

	public void function sendScheduledExports() {
		var nonRunningExports = $getPresideObject( "saved_export" ).selectData(
			  selectFields = [ "id" ]
			, filter       = "is_running = :is_running and next_run < :next_run and schedule != :schedule"
			, filterParams = { is_running = false, next_run = now(), schedule = "disabled" }
			, useCache     = false
		);

		for ( var export in nonRunningExports ) {
			runExport( export.id );
		}
	}

	public void function runExport( required string scheduledExportId ) {
		var exportDetail = getExportDetail( arguments.scheduledExportId )
		var lockName     = "runexport-#arguments.scheduledExportId#";

		try {
			lock name=lockName type="exclusive" timeout=1 {
				var newThreadId = "PresideExportScheduledExport-" & arguments.scheduledExportId & "-" & CreateUUId();
				var newLogId    = createExportHistoryLog( arguments.scheduledExportId, newThreadId );

				transaction {
					if ( exportIsRunning( arguments.scheduledExportId ) ) {
						return;
					}

					markExportAsRunning( arguments.scheduledExportId, newThreadId );
				}

				markExportAsStarted( arguments.scheduledExportId );
				runExportWithinThread(
					  scheduledExportId = arguments.scheduledExportId
					, historyLogId      = newLogId
					, threadId          = newThreadId
				);
			}
		} catch (any e) {
			$raiseError(e);
		}
	}

	public void function runExportWithinThread(
		  required string scheduledExportId
		, required string historyLogId
		, required string threadId
	) {
		var start           = getTickCount();
		var success         = false;
		var tu              = _getThreadUtil();

		try {
			$getRequestContext().setUseQueryCache( false );

			success = $getColdbox().runEvent(
				  event          = "ScheduledExportHelpers.runScheduledExport"
				, private        = true
				, eventArguments = { args={ scheduledExportId=scheduledExportId, historyExportId=historyLogId } }
			);
		} catch (any e) {
			$raiseError(e);
		} finally {
			markExportAsCompleted( arguments.historyLogId, arguments.scheduledExportId, success, getTickCount() - start );
		}
	}

	public numeric function markExportAsRunning(
		  required string exportId
		, required string threadId
	) {
		var exportDetail   = getExportDetail( arguments.exportId )
		var runningExports = _getRunningExports();

		runningExports[ arguments.threadId ] = { status="queued", thread=NullValue() };

		return $getPresideObject( "saved_export" ).updateData(
			  id   = arguments.exportId
			, data = {
				  is_running      = true
				, next_run        = ( ( exportDetail.schedule ?: "" ) eq "disabled" ) ? "" : getNextRunDate( exportDetail.schedule ?: "" )
				, running_thread  = arguments.threadId
				, running_machine = _getMachineId()
			  }
		);
	}

	public void function markExportAsStarted( required string threadId ) {
		var runningExports = _getRunningExports();

		runningExports[ arguments.threadId ] = { status="started" };
	}

	public numeric function markExportAsCompleted(
		  required string  historyExportId
		, required string  exportId
		, required boolean success
		, required numeric timeTaken
	) {
		completeExportHistoryLog(
			  historyExportId = arguments.historyExportId
			, success         = arguments.success
			, timeTaken       = arguments.timeTaken
		);

		var runningTasks = _getRunningExports();
		var exportRecord = getExportDetail( arguments.exportId );

		runningTasks.delete( exportRecord.running_thread ?: "", false );

		var updatedRows = $getPresideObject( "saved_export" ).updateData(
			  id   = arguments.exportId
			, data = {
				  is_running           = false
				, last_ran             = now()
				, next_run             = ( ( exportRecord.schedule ?: "" ) eq "disabled" ) ? "" : getNextRunDate( exportRecord.schedule ?: "" )
				, was_last_run_success = arguments.success
				, last_run_time_taken  = arguments.timeTaken
				, running_thread       = ""
				, running_machine      = ""
			  }
		);

		return updatedRows;
	}

	public string function createExportHistoryLog(
		  required string exportId
		, required string threadId
	) {
		var exporter = getExportDetail( arguments.exportId ).exporter ?: "";

		return $getPresideObject( "saved_export_history" ).insertData( data={
			  saved_export = arguments.exportId
			, exporter     = exporter
			, thread_id    = arguments.threadId
			, machine_id   = _getMachineId()
		} );
	}

	public numeric function completeExportHistoryLog(
		  required string  historyExportId
		, required boolean success
		, required numeric timeTaken
	) {
		return $getPresideObject( "saved_export_history" ).updateData(
			  id   = arguments.historyExportId
			, data = {
				  complete   = true
				, success    = arguments.success
				, time_taken = arguments.timeTaken
			}
		);
	}

	public boolean function exportIsRunning( required string exportId ) {
		transaction {
			var markedAsRunning = $getPresideObject( "saved_export" ).dataExists( filter = { id=arguments.exportId, is_running=true } );

			if ( markedAsRunning && !exportThreadIsRunning( arguments.taskKey ) ) {
				var logger = _getLogger( taskKey=arguments.taskKey );

				if ( logger.canError() ) {
					logger.error( "Task was marked as running but task thread is no longer running." );
				}

				markTaskAsCompleted(
					  taskKey   = arguments.taskKey
					, success   = false
					, timetaken = -1
				);
				return false;
			}

			return markedAsRunning;
		}
	}

	public boolean function exportThreadIsRunning( required string exportId ) {
		var export = $getPresideObject( "saved_export" ).selectData(
			  selectFields = [ "running_thread", "running_machine" ]
			, id           = arguments.exportId
		);

		if ( !export.recordCount || !Len( Trim( export.running_thread ?: "" ) ) ) {
			return false;
		}

		if ( export.running_machine != _getMachineId() ) {
			return true;
		}

		return _exportIsRunningOnLocalMachine( export );
	}

// PRIVATE HELPERS
	private array function _getLib() {
		return [
			  "/preside/system/services/taskmanager/lib/cron-parser-2.6-SNAPSHOT.jar"
			, "/preside/system/services/taskmanager/lib/commons-lang3-3.3.2.jar"
			, "/preside/system/services/taskmanager/lib/joda-time-2.9.4.jar"
			, "/preside/system/services/taskmanager/lib/cron-1.0.jar"
		];
	}

	private any function _createJodaTimeObject( required date cfmlDateTime ) {
		return CreateObject( "java", "org.joda.time.DateTime", _getLib() ).init( cfmlDateTime );
	}

	private any function _getCrontabExpressionObject( required string expression ) {
		return CreateObject( "java", "fc.cron.CronExpression", _getLib() ).init( arguments.expression );
	}

	private boolean function _exportIsRunningOnLocalMachine( required any task ){
		var runningTasks = _getRunningTasks();
		var threadRef    = runningTasks[ task.running_thread ].thread ?: NullValue();

		if ( IsNull( threadRef ) ) {
			return false;
		}
		try {
			return !threadRef.isDone() && !threadRef.isCancelled();
		} catch( any e ) {
			$raiseError( e );
		}

		return false;
	}

// GETTERS AND SETTERS
	private string function _getMachineId() {
		return _machineId;
	}
	private void function _setMachineId() {
		var localHost = CreateObject("java", "java.net.InetAddress").getLocalHost();

		_machineId = Left( localHost.getHostAddress() & "-" & localHost.getHostName(), 255 );
	}

	private struct function _getRunningExports() {
		return _runningExports;
	}
	private void function _setRunningExports( required struct runningExports ) {
		_runningExports = arguments.runningExports;
	}

	private any function _getThreadUtil() {
		return _threadUtil;
	}
	private void function _setThreadUtil( required any threadUtil ) {
		_threadUtil = arguments.threadUtil;
	}
}