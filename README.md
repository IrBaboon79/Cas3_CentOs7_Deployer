# Cas3_CentOs7_Deployer
-----------------------
This is a shellscript (bash v4) which turns a clean minimal CentOS 7.x into a Cassandra 3 Node.

Note there are 2 additional scripts under /SW which are expected to exist as well.

These additional scripts serve as templates for an automated maintenance task and it will trigger a weekly repair action for nodes in the respective cluster based on a simple, yet effective, scheme for clusters with <250 nodes.

Preparation
-----------
Deploy script has several configuration items - mostly around initial paths and locations of external files (see below).

It expects a few files to be available so that they can be taken care of as well.

The external files originate from their own respective sources and are assumed to exist, there is some validation.

External Files
--------------
- Oracle JAVA Runtime v1.8
- Apache Cassandra v3.x
- the mx4j-tools package (v3.02 or more recent)
- jemalloc-3.6.0-1.el7.x86_64.rpm (or newer)

Operation
----------
1) ssh into your CentOS machine
2) prepare your storage accordingly and figure out the folder where your desired storage location is mounted.
3) as a root user, copy the scripts and external files to some temporary location (your/root home is fine...)
4) execute the deploy script
5) answer questions and let it run...

The script will take care of:
-----------------------------
1) Extracting JRE and set it up accordingly.

   Note: update JRE by simply extracting another version and updating the symlink
2) Extracting cassandra to /cassandra
3) systemctl parameters, systemd units, etc.. will all be set permantently/created as needed
4) folder structure for cassandra database related files wil be created (location will be asked)
5) maintenance scripts will be installed as systemd timer
6) several other minor things here and there...

Things to do AFTERWARDS:
------------------------
1) Configure your firewall/zones accordingly
2) Configure cassandra network related items
3) Start the respective systemd units
4) Check everything is working as expected
5) Reboot the box, confirm all remains working as expected.


