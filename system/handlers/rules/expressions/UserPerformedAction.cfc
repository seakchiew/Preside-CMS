/**
 * Expression handler for "User has performed some action in some time frame"
 *
 * @feature websiteUsers
 * @expressionContexts user
 */
component {

	property name="rulesEngineOperatorService" inject="rulesEngineOperatorService";
	property name="websiteUserActionService"   inject="websiteUserActionService";

	/**
	 * @action.fieldType   websiteUserAction
	 * @action.multiple    false
	 */
	private boolean function evaluateExpression(
		  required string  action
		,          boolean _has = true
		,          struct  _pastTime
	) {
		if ( ListLen( action, "." ) != 2 ) {
			return false;
		}

		var result = websiteUserActionService.hasPerformedAction(
			  type     = ListFirst( action, "." )
			, action   = ListLast( action, "." )
			, userId   = payload.user.id ?: ""
			, dateFrom = _pastTime.from ?: ""
			, dateTo   = _pastTime.to   ?: ""
		);

		return _has ? result : !result;
	}

}