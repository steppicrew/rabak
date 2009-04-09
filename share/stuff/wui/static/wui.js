
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

    api('setlist', null, function(data) {
        console.log(data);
        if (data.error) {
            // error stuff
            return;
        }

        var html= [];
        for (var sets_i in data.sets) {
            var set= data.sets[sets_i];
            html.push('<li><a href="#show_backup_result:bakset=' + set.name + '">' + set.title + '</a></li>');
        }

        $("#sidebar").html('<ol>' + html.join('') + '</ol>');
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
