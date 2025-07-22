<?php
return array(
array(
                                'id'            => '1',
                                'driver'        => 'Trash',
                                'path'          => '../files/.trash/',
                                'winHashFix'    => DIRECTORY_SEPARATOR !== '/', // to make hash same to Linux one on windows too
                                'uploadDeny'    => array('all'),                // Recommend the same settings as the original volume that uses the trash
                                'uploadAllow'   => array('all'),                // allow everything for now - narrow scope later
                                //'uploadAllow' => array('image/x-ms-bmp', 'image/gif', 'image/jpeg', 'image/png', 'image/x-icon'. 'text/plain'), // Same as above
                                'uploadOrder'   => array('deny', 'allow'),      // Same as above
                                'accessControl' => 'access',                    // Same as above
                        ),
array(
                                'driver'        => 'LocalFileSystem',
                                'path'          => '/foundry_instances/campaigns/',
                                'winHashFix'    => DIRECTORY_SEPARATOR !== '/', // to make hash same to Linux one on windows too
                                'uploadDeny'    => array('all'),                // Recommend the same settings as the original volume that uses the trash
                                'uploadAllow'   => array('all'),                // allow everything for now - narrow scope later
                                //'uploadAllow' => array('image/x-ms-bmp', 'image/gif', 'image/jpeg', 'image/png', 'image/x-icon'. 'text/plain'), // Same as above
                                'uploadOrder'   => array('deny', 'allow'),      // Same as above
                                'accessControl' => 'access',                    // Same as above
                        ),
array(
                                'driver'        => 'LocalFileSystem',
                                'path'          => '/foundry_instances/oneshots/',
                                'winHashFix'    => DIRECTORY_SEPARATOR !== '/', // to make hash same to Linux one on windows too
                                'uploadDeny'    => array('all'),                // Recommend the same settings as the original volume that uses the trash
                                'uploadAllow'   => array('all'),                // allow everything for now - narrow scope later
                                //'uploadAllow' => array('image/x-ms-bmp', 'image/gif', 'image/jpeg', 'image/png', 'image/x-icon'. 'text/plain'), // Same as above
                                'uploadOrder'   => array('deny', 'allow'),      // Same as above
                                'accessControl' => 'access',                    // Same as above
                        ),
);