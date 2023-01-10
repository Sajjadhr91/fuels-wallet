import { createStore } from '@fuel-wallet/xstore';

import { accountEvents, unlockEvents } from './systems/Account/events';
import { networkEvents } from './systems/Network/events';

import { accountMachine, unlockMachine } from '~/systems/Account/machines';
import { networksMachine } from '~/systems/Network/machines';

export enum Services {
  unlock = 'unlock',
  accounts = 'accounts',
  networks = 'networks',
}

export type StoreMachines = typeof services;

const services = {
  accounts: () => accountMachine,
  networks: () => networksMachine,
  unlock: () => unlockMachine,
};

export const store = createStore(services, {
  events: (store) => ({
    ...accountEvents(store),
    ...networkEvents(store),
    ...unlockEvents(store),
  }),
});

export type Store = typeof store;
