# FPC MQTT Client Component

This is a simple self-contained MQTT V5.0 client component for Free Pascal.

It does not require any 3rd party networking libraries installed because it is built with TInetSocket from the SSockets unit, which is part of the standard FPC distribution.

This component does also not rely on the LCL, it comes with no installable IDE packages, just copy the two units into your project or put them into your unit search path.

There is an example in the demo folder which is mainly used for testing and experimenting during development, but it also serves as an example.

The client should implement just enough of the MQTT5 protocol to be able to connect to an MQTT5 server, subscribe and publish. I am using the official OASIS MQTT 5.0 document to implement the protocol (the chapter annotations in the source code refer to this document) and test against my Mosquitto server that is part of my Home Assistant installation and also against the official Mosquitto test server. The Home Assistant MQTT Broker is also the main motivation for this client to come into existence in the first place.

## Work in Progress

If you are interested in this, then you should click the "watch" button in GitHub and be prepared to wait a little longer because in its current state it is still incomplete, if you want to try it anyways then be prepared for breaking API changes without notice until I got most of the stuff implemented.

## Already implemented

* connect (plain and SSL)
* auth with username/password
* auth with cert + key
* subscribe
* subscription ID
* unsubscribe
* publish
* retain
* response topic
* correlation data
* QoS 1
* QoS 2

## Still missing (ordered by priority)

* will
* pluggable alternative auth methods
