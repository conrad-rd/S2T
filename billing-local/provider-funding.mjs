import { integer } from './money.mjs';

export function providerFunding(grossMicros, providerMicros, consumedMicros = 0) {
  integer(grossMicros, 0, Number.MAX_SAFE_INTEGER, 'Net payments');
  integer(providerMicros, 0, grossMicros, 'Provider allocation');
  integer(consumedMicros, 0, Number.MAX_SAFE_INTEGER, 'Settled usage');
  const earnedProviderMicros = Math.min(providerMicros, consumedMicros);
  const batchMicros = 5000000;
  const allocation = (sharePercent, allocatedMicros) => {
    const earnedMicros = sharePercent === 70
      ? Math.floor(earnedProviderMicros / 10) * 7
      : earnedProviderMicros - Math.floor(earnedProviderMicros / 10) * 7;
    return { sharePercent, allocatedMicros, earnedMicros,
      cumulativeBatchedMicros: Math.floor(earnedMicros / batchMicros) * batchMicros };
  };
  const openrouterMicros = Math.floor(providerMicros / 10) * 7;
  return {
    currency: 'usd',
    grossMicros,
    providerMicros,
    batchMicros,
    earnedProviderMicros,
    retainedBeforeTaxAndFeesMicros: grossMicros - providerMicros,
    providers: {
      openrouter: allocation(70, openrouterMicros),
      assemblyai: allocation(30, providerMicros - openrouterMicros),
    },
    transfersAutomated: false,
    availableForPayout: null,
  };
}
