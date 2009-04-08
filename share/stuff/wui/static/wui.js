
jQuery(function($) {

    $('body').html(
        '<div id="head"></div><div id="body"></div>'
    );

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

    api('setlist', function(data) {
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

});
