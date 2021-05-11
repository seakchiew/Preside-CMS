/**
 * The formbuilder_formitem object represents an individual item within a form builder form.
 * This could be a form control, some free text, etc.
 *
 * @nolabel
 */
component displayname="Form builder: Item" extends="preside.system.base.SystemPresideObject" {
	property name="form"     relationship="many-to-one" relatedto="formbuilder_form"     required=true  indexes="sortorder|1";
	property name="question" relationship="many-to-one" relatedto="formbuilder_question" required=false;

	property name="sort_order"    type="numeric" dbtype="int"     required=true indexes="sortorder|2";
	property name="item_type"     type="string"  dbtype="varchar" required=true maxlength=100;
	property name="configuration" type="string"  dbtype="text"    required=false;
}