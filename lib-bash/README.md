# Quick and dirty

## Make all \*.sh files eXecutable

`find . -type f -name "*.sh" ! -perm -111 -exec chmod +x {} \;`
