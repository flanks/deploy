#!/bin/bash
# Update Roundcube config to add calendar plugin
sed -i "s/\$config\['plugins'\] = \['archive', 'zipdownload', 'managesieve'\]/\$config['plugins'] = ['archive', 'zipdownload', 'managesieve', 'calendar']/" /opt/eurion/webmail/config/config.inc.php
grep plugins /opt/eurion/webmail/config/config.inc.php
