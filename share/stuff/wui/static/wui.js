
jQuery(function($) {

    $('body').html(
        '<div id="head"></div><div id="body"></div>'
    );

    var api= function(cmd, args, callback, errorCallback) {
        jQuery.ajax({
            url: "/api",
            type: "GET",
            data: { cmd: cmd },
            dataType: "json",
            success: function(data, status) {
                if (data.result && errorCallback) {
                    errorCallback(data);
                    return;
                }
                callback(data);
            },
            error: function(xhr, status, e) {
                errorCallback ? errorCallback({ result: -1 }) : callback({ result: -1 });
            }
        });
    };

    api('setlist', null, function(data) {
        console.log(data);
        if (data.result) {
            // error stuff
            return;
        }

        var html= [];
        for (var sets_i in data.sets) {
            var set= data.sets[sets_i];
            html.push('<li>' + set.title + '</li>');
        }

        $("#body").html('<ol>' + html.join('') + '</ol>');
    });

    api('backup_result', null, function(data) {
        console.log(data);
    })

    api('test', null, function(data) {
        console.log(data);
    })

});
