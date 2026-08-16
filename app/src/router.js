import { createRouter, createWebHashHistory } from 'vue-router'

import Dashboard from './pages/Dashboard.vue'
import Transactions from './pages/Transactions.vue'
import Record from './pages/Record.vue'
import Family from './pages/Family.vue'
import Settings from './pages/Settings.vue'
import Accounts from './pages/Accounts.vue'
import Loans from './pages/Loans.vue'
import Recurring from './pages/Recurring.vue'
import SaveBattle from './pages/SaveBattle.vue'

export const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', component: Dashboard },
    { path: '/tx', component: Transactions },
    { path: '/record', component: Record },
    { path: '/family', component: Family },
    { path: '/me', component: Settings },
    { path: '/accounts', component: Accounts },
    { path: '/loans', component: Loans },
    { path: '/recurring', component: Recurring },
    { path: '/save', component: SaveBattle },
  ],
})
