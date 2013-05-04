(function( kohadb, $, undefined ) {
    kohadb.initialize = function (callback) {
        $.indexedDB("koha", {
            "version": 1,
            "schema": {
                "1": function(versionTransaction){
                    var patrons = versionTransaction.createObjectStore("patrons", {
                        "keyPath": "cardnumber"
                    });
                    var items = versionTransaction.createObjectStore("items", {
                        "keyPath": "barcode"
                    });
                    var styles = versionTransaction.createObjectStore("issues", {
                        "keyPath": "barcode"
                    });
                    var styles = versionTransaction.createObjectStore("transactions", {
                        "keyPath": "barcode"
                    });
                },
            }
        }).done(function(){
            if (typeof callback === 'function') {
                callback();
            }
        });
    };
}( window.kohadb = window.bndb || {}, jQuery ));
