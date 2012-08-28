Debian Create Image
===================

A basic script to help with creating Debian EMIs for use with Eucalyptus (and maybe AWS). 

This script uses debootstrap to create a basic system installation with some extra packages for usability. After the initial installation, basic configurations are completed such as setting up /etc/fstab for the hypervisor being used, setting up locales, networking, setting up basic metadata scripting and UDev networking rules. The resulting image _should_ be ready to be uploaded to your cloud along with the kernel and ramdisk installed with the system.

The script was created in a way to hopefully make some basic changes to it easy. The variables at the top of the script will change the behavior so if possible try changing these first. There are also some basic comments to help to understand the script a little more.
