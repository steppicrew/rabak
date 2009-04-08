
jQuery(function($) {

    var api= function(cmd, callback) {
        jQuery.ajax({
            url: "/api",
            type: "GET",
            data: { cmd: cmd },
            dataType: "json",
            success: function(data, status) {
                if (callback) callback(data);
            },
            error: function(xhr, status, e) {
                if (callback) callback({});
            }
        });
    };

    api('setlist', function(result) {
        console.log(result);
        $("body").html(result);
    });

});
