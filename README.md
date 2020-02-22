Feldmex aims to be the first ever trustless free market options exchange.
Feldmex is starting by providing bitcoin and ethereum options contracts.
Feldmex is built ontop of ethereum smart contracts made with solidity which are interacted with through javascript.
This project contains a scripts fulder which may be run to interact with the smart contracts.
This project is built using the truffle js framework.

This project was developed whith the following dependencies
node js,
npm,
truffle js, and
ganache cli.
Both truffle and ganache cli can be installed with

sudo npm install -g truffle

sudo npm install -g ganache-cli

Ganache cli may be substituted with any other local etherem instance.
I have made a file outside of this project named ganacheLauncher.sh to quickly get a local ethereum instance running without having to type the same long command every time.

ganacheLauncher.sh contains only the following line

ganache-cli -p 8545 -q
