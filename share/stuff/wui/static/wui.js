
jQuery(function($) {

    // TODO: stop pending api calls
    var api= function(cmd, args, callback, errorCallback) {
        if (!args) args= {};
        args['cmd']= cmd;
        jQuery.ajax({
            url: "/api",
            type: "GET",
            data: args,
            dataType: "json",
            success: function(data, status) {
                if (data.error && errorCallback) {
                    errorCallback(data);
                    return;
                }
                callback(data);
            },
            error: function(xhr, status, e) {
                var result= { error: -1, error_text: 'Ajax call returned ' + status };
                errorCallback ? errorCallback(result) : callback(result);
            }
        });
    };

// TEST ----------------------- [[

    api('get_baksets', null, function(data) {
        console.log(data);
        if (data.error) {
            // error stuff
            return;
        }

        var html= [];
        for (var baksets_i in data.baksets) {
            var bakset= data.baksets[baksets_i];
            html.push('<li><a href="#show_backup_result:bakset=' + bakset.name + '">' + bakset.title + '</a></li>');
        }

        $("#sidebar").html('<ol>' + html.join('') + '</ol>'
            + '<hr />'
            + '<a href="#test1">Test1</a>'
        );
    });

    api('test', null, function(data) {
        console.log(data);
    })

// TEST ----------------------- ]]


    var cmds= {};
    cmds.show_backup_result= function(params) {
        api('backup_result', params, function(data) {
            console.log(data);

            $("#body").html('<h1>' + data.result.bakset + '</h1>');
        })
    };
    cmds.test1= function(params) {

// kann mit fehlenden daten umgehen
// alternative: http://code.google.com/p/protovis-js/downloads/list

        $("#body").html('<div id="placeholder" style="width:600px;height:300px;"></div>');

$(function () {
    var d1 = [];
    for (var i = 0; i < 14; i += 0.5)
        d1.push([i, Math.sin(i)]);

    var d2 = [[0, 3], [4, 8], [8, 5], [9, 13]];

    // a null signifies separate line segments
    var d3 = [[0, 12], [7, 12], null, [7, 2.5], [12, 2.5]];

    $.plot($("#placeholder"), [ d1, d2, d3 ]);
});

        
    };

    $('a').live('click', function() {
        console.log("Clicked:", $(this).attr('href'));

        var href= $(this).attr('href');
        
        // Not an internal link, pass on to browser
        if (href.substr(0, 1) != '#') return true;

        var paramsl= href.substr(1).split(/[:=]/);
        var cmd= paramsl.shift();
        var cmdFn= cmds[cmd];
        if (!cmdFn) {
            console.error('Command "' + cmd + '" not defined');
            return false;
        }

        var params= {};
        while (paramsl.length) {
            var key= paramsl.shift();
            params[key]= paramsl.shift();
        }

                        // Wenn true zurckgegeben wird, landets in der history und ist bookmarkable
        cmdFn(params);  // return cmdFn(params) ???
        return false;   // Oder evt abhaenging von nem params['omit_history'] ??
    });

});
