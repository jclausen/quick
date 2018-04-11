component accessors="true" {

    /*====================================
    =            Dependencies            =
    ====================================*/
    property name="builder"            inject="QueryBuilder@qb";
    property name="wirebox"            inject="wirebox";
    property name="str"                inject="Str@str";
    property name="settings"           inject="coldbox:modulesettings:quick";
    property name="validationManager"  inject="ValidationManager@cbvalidation";
    property name="interceptorService" inject="coldbox:interceptorService";

    /*===========================================
    =            Metadata Properties            =
    ===========================================*/
    property name="entityName";
    property name="mapping";
    property name="fullName";
    property name="table";
    property name="readonly"        default="false";
    property name="attributeCasing" default="none";
    property name="key"             default="id";
    property name="attributes"      default="*";
    property name="metadata";

    /*=====================================
    =            Instance Data            =
    =====================================*/
    property name="attributesData";
    property name="originalAttributes";
    property name="relationships";
    property name="eagerLoad";
    property name="loaded";

    function init() {
        setDefaultProperties();
        return this;
    }

    function setDefaultProperties() {
        setAttributesData( {} );
        setOriginalAttributes( {} );
        setRelationships( {} );
        setEagerLoad( [] );
        setLoaded( false );
    }

    function onDIComplete() {
        metadataInspection();
    }

    /*==================================
    =            Attributes            =
    ==================================*/

    function getKeyValue() {
        return variables.attributesData[ getKey() ];
    }

    function getAttributesData() {
        return duplicate( variables.attributesData );
    }

    function getAttributeNames() {
        return structKeyArray( variables.attributesData );
    }

    function clearAttribute( name, setToNull = false ) {
        if ( setToNull ) {
            variables.attributesData[ applyCasingTransformation( name, getAttributeCasing() ) ] = javacast( "null", "" );
        }
        else {
            variables.attributesData.delete( name );
        }
        return this;
    }

    function setAttributesData( attributes ) {
        guardAgainstReadOnlyAttributes( attributes );
        if ( isNull( arguments.attributes ) ) {
            setLoaded( false );
            variables.attributesData = {};
            return this;
        }
        variables.attributesData = attributes.reduce( function( acc, name, value ) {
            var key = name;
            if ( isColumnAlias( name ) ) {
                key = getColumnForAlias( name );
            }
            acc[ key ] = value;
            return acc;
        }, {} );
        return this;
    }

    function fill( attributes ) {
        for ( var key in attributes ) {
            invoke( this, "set#key#", { value = attributes[ key ] } );
        }
        return this;
    }

    function hasAttribute( name ) {
        return structKeyExists( variables.attributesData, name );
    }

    function isColumnAlias( name ) {
        return ! isSimpleValue( getAttributes() ) &&
            structKeyExists( getAttributes(), name );
    }

    function getColumnForAlias( name ) {
        return getAttributes()[ name ];
    }

    function transformAttributeAliases( attributes ) {
        return attributes.reduce( function( acc, key, value ) {
            if ( isColumnAlias( key ) ) {
                key = getColumnForAlias( key );
            }
            acc[ key ] = value;
            return acc;
        }, {} );
    }

    function setOriginalAttributes( attributes ) {
        variables.originalAttributes = duplicate( attributes );
        return this;
    }

    function isDirty() {
        return ! deepEqual( getOriginalAttributes(), getAttributesData() );
    }

    function getAttribute( name ) {
        return variables.attributesData[ name ];
    }

    function setAttribute( name, value ) {
        guardAgainstReadOnlyAttribute( name );
        if ( isColumnAlias( name ) ) {
            name = getColumnForAlias( name );
        }
        variables.attributesData[ applyCasingTransformation( name, getAttributeCasing() ) ] = value;
        return this;
    }

    /*=====================================
    =            Query Methods            =
    =====================================*/

    function all() {
        return eagerLoadRelations(
            newQuery().from( getTable() ).get()
                .map( function( attributes ) {
                    return newEntity()
                        .setAttributesData( attributes )
                        .setOriginalAttributes( attributes )
                        .setLoaded( true );
                } )
        );
    }

    function get() {
        return eagerLoadRelations(
            getQuery().get().map( function( attributes ) {
                return newEntity()
                    .setAttributesData( attributes )
                    .setOriginalAttributes( attributes )
                    .setLoaded( true );
            } )
        );
    }

    function first() {
        var attributes = getQuery().first();
        return newEntity()
            .setAttributesData( attributes )
            .setOriginalAttributes( attributes )
            .setLoaded( true );
    }

    function find( id ) {
        fireEvent( "preLoad", { id = id, metadata = getMetadata() } );
        var data = getQuery()
            .when( ! isSimpleValue( getAttributes() ), function( q ) {
                q.select( arrayMap( structKeyArray( getAttributes() ), function( key ) {
                    return getColumnForAlias( key );
                } ) );
                q.addSelect( getKey() );
            } )
            .from( getTable() )
            .find( id, getKey() );
        if ( structIsEmpty( data ) ) {
            return;
        }
        return tap( loadEntity( data ), function( entity ) {
            fireEvent( "postLoad", { entity = entity } );
        } );
    }

    private function loadEntity( data ) {
        return newEntity()
            .setAttributesData( data )
            .setOriginalAttributes( data )
            .setLoaded( true );
    }

    function findOrFail( id ) {
        var entity = variables.find( id );
        if ( isNull( entity ) ) {
            throw(
                type = "EntityNotFound",
                message = "No [#getEntityName()#] found with id [#id#]"
            );
        }
        return entity;
    }

    function firstOrFail() {
        var attributes = getQuery().first();
        if ( structIsEmpty( attributes ) ) {
            throw(
                type = "EntityNotFound",
                message = "No [#getEntityName()#] found with constraints [#serializeJSON( getQuery().getBindings() )#]"
            );
        }
        return newEntity()
            .setAttributesData( attributes )
            .setOriginalAttributes( attributes )
            .setLoaded( true );
    }

    function newEntity() {
        return wirebox.getInstance( getFullName() );
    }

    function fresh() {
        return variables.find( getKeyValue() );
    }

    function refresh() {
        setRelationships( {} );
        setAttributesData( newQuery().from( getTable() ).find( getKeyValue(), getKey() ) );
        return this;
    }

    /*===========================================
    =            Persistence Methods            =
    ===========================================*/

    function save() {
        guardReadOnly();
        fireEvent( "preSave", { entity = this } );
        if ( getLoaded() ) {
            fireEvent( "preUpdate", { entity = this } );
            guardValid();
            newQuery()
                .where( getKey(), getKeyValue() )
                .update( getAttributesData().map( function( key, value, attributes ) {
                    return isNull( value ) ? { value = "", nulls = true, null = true } : value;
                } ) );
            setOriginalAttributes( getAttributesData() );
            setLoaded( true );
            fireEvent( "postUpdate", { entity = this } );
        }
        else {
            fireEvent( "preInsert", { entity = this } );
            guardValid();
            var result = newQuery().insert( getAttributesData() );
            var generatedKey = result.keyExists( "generated_key" ) ? result[ "generated_key" ] : result[ "generatedKey" ];
            setAttribute( getKey(), generatedKey );
            setOriginalAttributes( getAttributesData() );
            setLoaded( true );
            fireEvent( "postInsert", { entity = this } );
        }
        fireEvent( "postSave", { entity = this } );

        return this;
    }

    function delete() {
        guardReadOnly();
        fireEvent( "preDelete", { entity = this } );
        newQuery().delete( getKeyValue(), getKey() );
        setLoaded( false );
        fireEvent( "postDelete", { entity = this } );
        return this;
    }

    function update( attributes = {} ) {
        fill( attributes );
        return save();
    }

    function create( attributes = {} ) {
        return newEntity().setAttributesData( attributes ).save();
    }

    function updateAll( attributes = {} ) {
        guardReadOnly();
        guardAgainstReadOnlyAttributes( attributes );
        return get().each( function( entity ) {
            entity.update( attributes );
        } );
    }

    function deleteAll( ids = [] ) {
        guardReadOnly();
        if ( ! arrayIsEmpty( ids ) ) {
            getQuery().whereIn( getKey(), ids );
        }
        get().each( function( entity ) {
            entity.delete();
        } );
        return this;
    }

    /*=====================================
    =            Relationships            =
    =====================================*/

    function hasRelationship( name ) {
        var md = this.getMetadata();
        param md.functions = [];
        return ! arrayIsEmpty( arrayFilter( md.functions, function( func ) {
            return compareNoCase( func.name, name ) == 0;
        } ) );
    }

    function isRelationshipLoaded( name ) {
        return structKeyExists( variables.relationships, name );
    }

    function getRelationship( name ) {
        return variables.relationships[ name ];
    }

    function setRelationship( name, value ) {
        if ( ! isNull( value ) ) {
            variables.relationships[ name ] = value;
        }
        return this;
    }

    function clearRelationships() {
        variables.relationships = {};
        return this;
    }

    function clearRelationship( name ) {
        variables.relationships.delete( name );
        return this;
    }

    private function belongsTo( relationName, foreignKey ) {
        var related = wirebox.getInstance( relationName );

        if ( isNull( arguments.foreignKey ) ) {
            arguments.foreignKey = applyCasingTransformation(
                [ related.getEntityName(), related.getKey() ],
                related.getAttributeCasing()
            );
        }
        if ( isNull( arguments.owningKey ) ) {
            arguments.owningKey = related.getKey();
        }
        return wirebox.getInstance( name = "BelongsTo@quick", initArguments = {
            wirebox = wirebox,
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            foreignKey = foreignKey,
            foreignKeyValue = hasAttribute( arguments.foreignKey ) ? getAttribute( arguments.foreignKey ) : "",
            owningKey = owningKey
        } );
    }

    private function hasOne( relationName, foreignKey ) {
        var related = wirebox.getInstance( relationName );
        if ( isNull( arguments.foreignKey ) ) {
            arguments.foreignKey = getKey();
        }
        if ( isNull( arguments.owningKey ) ) {
            arguments.owningKey = applyCasingTransformation(
                [ getEntityName(), getKey() ],
                getAttributeCasing()
            );
        }
        return wirebox.getInstance( name = "HasOne@quick", initArguments = {
            wirebox = wirebox,
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            foreignKey = foreignKey,
            foreignKeyValue = getKeyValue(),
            owningKey = owningKey
        } );
    }

    private function hasMany( relationName, foreignKey ) {
        var related = wirebox.getInstance( relationName );
        if ( isNull( arguments.foreignKey ) ) {
            arguments.foreignKey = applyCasingTransformation(
                [ getEntityName(), getKey() ],
                getAttributeCasing()
            );
        }
        if ( isNull( arguments.owningKey ) ) {
            arguments.owningKey = "#getEntityName()#_#getKey()#";
            arguments.owningKey = applyCasingTransformation(
                [ getEntityName(), getKey() ],
                getAttributeCasing()
            );
        }
        return wirebox.getInstance( name = "HasMany@quick", initArguments = {
            wirebox = wirebox,
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            foreignKey = foreignKey,
            foreignKeyValue = getKeyValue(),
            owningKey = owningKey
        } );
    }

    private function belongsToMany( relationName, table, foreignKey, relatedKey ) {
        var related = wirebox.getInstance( relationName );
        if ( isNull( arguments.table ) ) {
            if ( compareNoCase( related.getTable(), getTable() ) < 0 ) {
                arguments.table = lcase( "#related.getTable()#_#getTable()#" );
            }
            else {
                arguments.table = lcase( "#getTable()#_#related.getTable()#" );
            }
        }
        if ( isNull( arguments.relatedKey ) ) {
            arguments.relatedKey = applyCasingTransformation(
                [ related.getEntityName(), related.getKey() ],
                related.getAttributeCasing()
            );
        }
        if ( isNull( arguments.foreignKey ) ) {
            arguments.foreignKey = applyCasingTransformation(
                [ getEntityName(), getKey() ],
                getAttributeCasing()
            );

        }
        return wirebox.getInstance( name = "BelongsToMany@quick", initArguments = {
            wirebox = wirebox,
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            table = table,
            foreignKey = foreignKey,
            foreignKeyValue = getKeyValue(),
            relatedKey = relatedKey
        } );
    }

    private function hasManyThrough( relationName, intermediateName, foreignKey, intermediateKey, owningKey ) {
        var related = wirebox.getInstance( relationName );
        var intermediate = wirebox.getInstance( intermediateName );
        if ( isNull( arguments.intermediateKey ) ) {
            arguments.intermediateKey = applyCasingTransformation(
                [ intermediate.getEntityName(), intermediate.getKey() ],
                intermediate.getAttributeCasing()
            );
        }
        if ( isNull( arguments.foreignKey ) ) {
            arguments.foreignKey = applyCasingTransformation(
                [ getEntityName(), getKey() ],
                intermediate.getAttributeCasing()
            );
        }
        if ( isNull( arguments.owningKey ) ) {
            arguments.owningKey = getKey();
        }
        return wirebox.getInstance( name = "HasManyThrough@quick", initArguments = {
            wirebox = wirebox,
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            intermediate = intermediate,
            foreignKey = foreignKey,
            foreignKeyValue = getKeyValue(),
            intermediateKey = intermediateKey,
            owningKey = owningKey
        } );
    }

    private function polymorphicHasMany( relationName, prefix ) {
        var related = wirebox.getInstance( relationName );
        return wirebox.getInstance( name = "PolymorphicHasMany@quick", initArguments = {
            wirebox = wirebox,
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            foreignKey = "",
            foreignKeyValue = "",
            owningKey = "",
            prefix = prefix
        } );
    }

    private function polymorphicBelongsTo( prefix ) {
        var relationName = getAttribute(
            "#prefix#_type"
        );
        var related = wirebox.getInstance( relationName );
        return wirebox.getInstance( name = "PolymorphicBelongsTo@quick", initArguments = {
            wirebox = wirebox,
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            foreignKey = related.getKey(),
            foreignKeyValue = getAttribute( "#prefix#_id" ),
            owningKey = "",
            prefix = prefix
        } );
    }

    function with( relationName ) {
        if ( isSimpleValue( relationName ) && relationName == "" ) {
            return this;
        }
        relationName = isArray( relationName ) ? relationName : [ relationName ];
        arrayAppend( variables.eagerLoad, relationName, true );
        return this;
    }

    private function eagerLoadRelations( entities ) {
        if ( entities.empty() || arrayIsEmpty( variables.eagerLoad ) ) {
            return entities;
        }

        arrayEach( variables.eagerLoad, function( relationName ) {
            entities = eagerLoadRelation( relationName, entities );
        } );

        return entities;
    }

    private function eagerLoadRelation( relationName, entities ) {
        var keys = entities.map( function( entity ) {
            return invoke( entity, relationName ).getForeignKeyValue();
        } ).unique();
        var relatedEntity = invoke( entities.get( 1 ), relationName ).getRelated();
        var owningKey = invoke( entities.get( 1 ), relationName ).getOwningKey();
        var relations = relatedEntity.resetQuery().whereIn( owningKey, keys.get() ).get();

        return matchRelations( entities, relations, relationName );
    }

    private function matchRelations( entities, relations, relationName ) {
        var relationship = invoke( entities.get( 1 ), relationName );
        var groupedRelations = relations.groupBy( key = relationship.getOwningKey(), forceLookup = true );
        return entities.each( function( entity ) {
            var relationship = invoke( entity, relationName );
            if ( structKeyExists( groupedRelations, relationship.getForeignKeyValue() ) ) {
                entity.setRelationship( relationName, relationship.fromGroup(
                    groupedRelations[ relationship.getForeignKeyValue() ]
                ) );
            }
            else {
                entity.setRelationship( relationName, relationship.getDefaultValue() );
            }
        } );
    }

    /*=======================================
    =            QB Utilities            =
    =======================================*/

    public function resetQuery() {
        newQuery();
        return this;
    }

    public function newQuery() {
        variables.query = builder.newQuery()
            .setReturnFormat( function( q ) {
                return wirebox.getInstance(
                    name = "QuickCollection@quick",
                    initArguments = { collection = q }
                );
            } )
            .from( getTable() );
        return variables.query;
    }

    public function getQuery() {
        if ( ! structKeyExists( variables, "query" ) ) {
            variables.query = newQuery();
        }
        return variables.query;
    }

    /*=====================================
    =            Magic Methods            =
    =====================================*/

    function onMissingMethod( missingMethodName, missingMethodArguments ) {
        var columnValue = tryColumnName( missingMethodName, missingMethodArguments );
        if ( ! isNull( columnValue ) ) { return columnValue; }
        var q = tryScopes( missingMethodName, missingMethodArguments );
        if ( ! isNull( q ) ) {
            variables.query = q;
            return this;
        }
        var r = tryRelationships( missingMethodName );
        if ( ! isNull( r ) ) { return r; }
        // if this is a getter and we have a wildcard for attributes, assume it is currently missing
        if ( str.startsWith( missingMethodName, "get" ) ) {
            if ( isSimpleValue( getAttributes() ) && getAttributes() == "*" ) {
                return javacast( "null", "" );
            }
        }
        return forwardToQB( missingMethodName, missingMethodArguments );
    }

    private function tryColumnName( missingMethodName, missingMethodArguments ) {
        var getColumnValue = tryColumnGetters( missingMethodName );
        if ( ! isNull( getColumnValue ) ) { return getColumnValue; }
        var setColumnValue = tryColumnSetters( missingMethodName, missingMethodArguments );
        if ( ! isNull( setColumnValue ) ) { return setColumnValue; }
        return;
    }

    private function tryColumnGetters( missingMethodName ) {
        if ( ! str.startsWith( missingMethodName, "get" ) ) {
            return;
        }

        var columnName = applyCasingTransformation(
            str.capitalize( str.slice( missingMethodName, 4 ), true ),
            getAttributeCasing()
        );

        if ( isColumnAlias( columnName ) ) {
            return getAttribute( getColumnForAlias( columnName ) );
        }

        if ( hasAttribute( columnName ) ) {
            return getAttribute( columnName );
        }

        return;
    }

    private function tryColumnSetters( missingMethodName, missingMethodArguments ) {
        if ( ! str.startsWith( missingMethodName, "set" ) ) {
            return;
        }

        var columnName = applyCasingTransformation(
            str.capitalize( str.slice( missingMethodName, 4 ), true ),
            getAttributeCasing()
        );
        setAttribute( columnName, missingMethodArguments[ 1 ] );
        return missingMethodArguments[ 1 ];
    }

    private function tryRelationships( missingMethodName ) {
        if ( ! str.startsWith( missingMethodName, "get" ) ) {
            return;
        }

        var relationshipName = str.slice( missingMethodName, 4 );

        if ( ! hasRelationship( relationshipName ) ) {
            return;
        }

        if ( ! isRelationshipLoaded( relationshipName ) ) {
            setRelationship( relationshipName, invoke( this, relationshipName ).retrieve() );
        }

        return getRelationship( relationshipName );
    }

    private function tryScopes( missingMethodName, missingMethodArguments ) {
        if ( structKeyExists( variables, "scope#missingMethodName#" ) ) {
            return invoke( this, "scope#missingMethodName#", {
                query = getQuery(),
                args = missingMethodArguments
            } );
        }
        return;
    }

    private function forwardToQB( missingMethodName, missingMethodArguments ) {
        var result = invoke( getQuery(), missingMethodName, missingMethodArguments );
        if ( isSimpleValue( result ) ) {
            return result;
        }
        return this;
    }

    function getMemento() {
        return getAttributesData();
    }

    function $renderdata() {
        return getMemento();
    }

    /*=======================================
    =            Other Utilities            =
    =======================================*/

    private function tap( value, callback ) {
        callback( value );
        return value;
    }

    private function metadataInspection() {
        var md = getMetadata( this );
        setMetadata( md );
        setFullName( md.fullname );
        param md.mapping = listLast( md.fullname, "." );
        setMapping( md.mapping );
        param md.entityName = listLast( md.name, "." );
        setEntityName( md.entityName );
        param md.table = str.plural( str.snake( getEntityName() ) );
        setTable( md.table );
        param md.readonly = false;
        setReadOnly( md.readonly );
        param settings.defaultAttributeCasing = "none";
        param md.attributecasing = settings.defaultAttributeCasing;
        setAttributeCasing( md.attributecasing );
        param md.properties = [];
        setAttributesFromProperties( md.properties );
    }

    private function setAttributesFromProperties( properties ) {
        if ( properties.isEmpty() ) {
            return setAttributes( "*" );
        }
        return setAttributes(
            properties.reduce( function( acc, prop ) {
                param prop.column = prop.name;
                param prop.persistent = true;
                if ( prop.persistent ) {
                    acc[ prop.name ] = prop.column;
                }
                return acc;
            }, {} )
        );
    }

    private function applyCasingTransformation( word, casing = "none" ) {
        if ( casing == "none" ) {
            return isArray( word ) ? arrayToList( word, "" ) : word;
        }

        return invoke(
            str,
            casing,
            { 1 = isArray( word ) ? arrayToList( word, " " ) : word }
        );
    }

    private function deepEqual( required expected, required actual ) {
        // Numerics
        if (
            isNumeric( arguments.actual ) &&
            isNumeric( arguments.expected ) &&
            toString( arguments.actual ) == toString( arguments.expected )
        ) {
            return true;
        }

        // Other Simple values
        if (
            isSimpleValue( arguments.actual ) &&
            isSimpleValue( arguments.expected ) &&
            arguments.actual == arguments.expected
        ) {
            return true;
        }

        // Queries
        if ( isQuery( arguments.actual ) && isQuery( arguments.expected ) ) {
            // Check number of records
            if ( arguments.actual.recordCount != arguments.expected.recordCount ) {
                return false;
            }

            // Get both column lists and sort them the same
            var actualColumnList = listSort( arguments.actual.columnList, "textNoCase" );
            var expectedColumnList = listSort( arguments.expected.columnList, "textNoCase" );

            // Check column lists
            if ( actualColumnList != expectedColumnList ) {
                return false;
            }

            for ( var i = 1; i <= arguments.actual.recordCount; i++ ) {
                for ( var column in listToArray( actualColumnList ) ) {
                    if ( arguments.actual[ column ][ i ] != arguments.expected[ column ][ i ] ) {
                        return false;
                    }
                }
            }

            return true;
        }

        // UDFs
        if (
            isCustomFunction( arguments.actual ) &&
            isCustomFunction( arguments.expected ) &&
            arguments.actual.toString() == arguments.expected.toString()
        ) {
            return true;
        }

        // XML
        if (
            IsXmlDoc( arguments.actual ) &&
            IsXmlDoc( arguments.expected ) &&
            toString( arguments.actual ) == toString( arguments.expected )
        ) {
            return true;
        }

        // Arrays
        if ( isArray( arguments.actual ) && isArray( arguments.expected ) ) {
            if ( arrayLen( arguments.actual ) neq arrayLen( arguments.expected ) ) {
                return false;
            }

            for ( var i = 1; i <= arrayLen( arguments.actual ); i++ ) {
                if ( arrayIsDefined( arguments.actual, i ) && arrayIsDefined( arguments.expected, i ) ) {
                    // check for both nulls
                    if ( isNull( arguments.actual[ i ] ) && isNull( arguments.expected[ i ] ) ) {
                        continue;
                    }
                    // check if one is null mismatch
                    if ( isNull( arguments.actual[ i ] ) || isNull( arguments.expected[ i ] ) ) {
                        return false;
                    }
                    // And make sure they match
                    if ( ! deepEqual( arguments.actual[ i ], arguments.expected[ i ] ) ) {
                        return false;
                    }
                    continue;
                }
                // check if both not defined, then continue to next element
                if ( ! arrayIsDefined( arguments.actual, i ) && ! arrayIsDefined( arguments.expected, i ) ) {
                    continue;
                } else {
                    return false;
                }
            }

            return true;
        }

        // Structs / Object
        if ( isStruct( arguments.actual ) && isStruct( arguments.expected ) ) {

            var actualKeys = listSort( structKeyList( arguments.actual ), "textNoCase" );
            var expectedKeys = listSort( structKeyList( arguments.expected ), "textNoCase" );

            if ( actualKeys != expectedKeys ) {
                return false;
            }

            // Loop over each key
            for ( var key in arguments.actual ) {
                // check for both nulls
                if ( isNull( arguments.actual[ key ] ) && isNull( arguments.expected[ key ] ) ) {
                    continue;
                }
                // check if one is null mismatch
                if ( isNull( arguments.actual[ key ] ) || isNull( arguments.expected[ key ] ) ) {
                    return false;
                }
                // And make sure they match when actual values exist
                if ( ! deepEqual( arguments.actual[ key ], arguments.expected[ key ] ) ) {
                    return false;
                }
            }

            return true;
        }

        return false;
    }

    /*=================================
    =           Validation            =
    =================================*/

    private function guardValid() {
        if ( isNull( validationManager ) ) {
            return this;
        }

        param settings.automaticValidation = false;
        if ( ! settings.automaticValidation ) {
            return this;
        }

        var validationResult = validationManager.validate( this );
        if ( ! validationResult.hasErrors() ) {
            return this;
        }

        throw(
            type = "InvalidEntity",
            message = "The #getEntityName()# entity failed to pass validation",
            detail = validationResult.getAllErrorsAsJson()
        );
    }

    /*=================================
    =            Read Only            =
    =================================*/

    private function guardReadOnly() {
        if ( isReadOnly() ) {
            throw(
                type = "QuickReadOnlyException",
                message = "[#getEntityName()#] is marked as a read-only entity."
            );
        }
    }

    private function isReadOnly() {
        return getReadOnly();
    }

    private function guardAgainstReadOnlyAttributes( attributes ) {
        for ( var name in attributes ) {
            guardAgainstReadOnlyAttribute( name );
        }
    }

    private function guardAgainstReadOnlyAttribute( name ) {
        if ( isReadOnlyAttribute( name ) ) {
            throw(
                type = "QuickReadOnlyException",
                message = "[#name#] is a read-only property on [#getEntityName()#]"
            );
        }
    }

    private function isReadOnlyAttribute( name ) {
        var md = getMetadata();
        if ( ! md.keyExists( "properties" ) || arrayIsEmpty( md.properties ) ) {
            return false;
        }
        var foundProperties = arrayFilter( md.properties, function( prop ) {
            return prop.name == name;
        } );
        if ( arrayIsEmpty( foundProperties ) ) {
            return false;
        }
        return foundProperties[ 1 ].keyExists( "readonly" ) && foundProperties[ 1 ].readonly;
    }

    /*==============================
    =            Events            =
    ==============================*/

    function fireEvent( eventName, eventData ) {
        eventData.entityName = getEntityName();
        if ( eventMethodExists( eventName ) ) {
            invoke( this, eventName, { eventData = eventData } );
        }
        if ( ! isNull( interceptorService ) ) {
            interceptorService.processState( "quick" & eventName, eventData );
        }
    }

    private function eventMethodExists( eventName ) {
        return variables.keyExists( eventName );
    }

}
