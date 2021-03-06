module Cardano.CLI.Shelley.Run.Pool
  ( runPoolCmd
  ) where

import           Cardano.Prelude

import qualified Data.Set as Set

import           Control.Monad.Trans.Except (ExceptT)
import           Control.Monad.Trans.Except.Extra (firstExceptT, newExceptT)

import           Cardano.Api (ShelleyCoin, ShelleyStakePoolMargin,
                   ShelleyStakePoolRelay, StakingVerificationKey (..),
                   mkShelleyStakingCredential, readStakingVerificationKey,
                   readVerificationKeyStakePool, shelleyRegisterStakePool,
                   shelleyRetireStakePool, writeCertificate,
                   SigningKey(..), writeSigningKey,
                   writeVerificationKeyStakePool)

import qualified Shelley.Spec.Ledger.Address as Shelley
import           Shelley.Spec.Ledger.Keys (hash, hashKey)
import qualified Shelley.Spec.Ledger.Slot as Shelley

import           Cardano.Config.Shelley.ColdKeys (genKeyPair)
import           Cardano.Config.Shelley.VRF

import           Cardano.CLI.Errors (CliError(..))
import           Cardano.CLI.Shelley.Commands



runPoolCmd :: PoolCmd -> ExceptT CliError IO ()
runPoolCmd (PoolKeyGen vk sk) = runStakePoolKeyGen vk sk
runPoolCmd (PoolRegistrationCert sPvkey vrfVkey pldg pCost pMrgn rwdVerFp ownerVerFps relays outfp) =
  runStakePoolRegistrationCert sPvkey vrfVkey pldg pCost pMrgn rwdVerFp ownerVerFps relays outfp
runPoolCmd (PoolRetirmentCert sPvkeyFp retireEpoch outfp) =
  runStakePoolRetirementCert sPvkeyFp retireEpoch outfp
runPoolCmd cmd = liftIO $ putStrLn $ "runPoolCmd: " ++ show cmd


--
-- Stake pool command implementations
--

runStakePoolKeyGen :: VerificationKeyFile -> SigningKeyFile -> ExceptT CliError IO ()
runStakePoolKeyGen (VerificationKeyFile vkFp) (SigningKeyFile skFp) = do
  (vkey, skey) <- liftIO genKeyPair
  firstExceptT CardanoApiError . newExceptT $ writeVerificationKeyStakePool vkFp vkey
  --TODO: writeSigningKey should really come from Cardano.Config.Shelley.ColdKeys
  firstExceptT CardanoApiError . newExceptT $ writeSigningKey skFp (SigningKeyShelley skey)

-- | Create a stake pool registration cert.
-- TODO: Metadata and more stake pool relay support to be
-- added in the future.
runStakePoolRegistrationCert
  :: VerificationKeyFile
  -- ^ Stake pool verification key.
  -> VerificationKeyFile
  -- ^ VRF Verification key.
  -> ShelleyCoin
  -- ^ Pool pledge.
  -> ShelleyCoin
  -- ^ Pool cost.
  -> ShelleyStakePoolMargin
  -- ^ Pool margin.
  -> VerificationKeyFile
  -- ^ Reward account verification staking key.
  -> [VerificationKeyFile]
  -- ^ Pool owner verification staking key(s).
  -> [ShelleyStakePoolRelay]
  -- ^ Stake pool relays.
  -> OutputFile
  -> ExceptT CliError IO ()
runStakePoolRegistrationCert
  (VerificationKeyFile sPvkeyFp)
  (VerificationKeyFile vrfVkeyFp)
  pldg
  pCost
  pMrgn
  (VerificationKeyFile rwdVerFp)
  ownerVerFps
  relays
  (OutputFile outfp) = do
    -- Pool verification key
    stakePoolVerKey <- firstExceptT CardanoApiError . newExceptT $ readVerificationKeyStakePool sPvkeyFp

    -- VRF verification key
    -- TODO: VRF key reading and writing has two versions and needs to be sorted out.
    vrfVerKey <- firstExceptT VRFCliError $ readVRFVerKey vrfVkeyFp

    -- Pool reward account
    StakingVerificationKeyShelley rewardAcctVerKey <-
      firstExceptT CardanoApiError . newExceptT $ readStakingVerificationKey rwdVerFp
    let rewardAccount = Shelley.mkRwdAcnt . mkShelleyStakingCredential $ hashKey rewardAcctVerKey

    -- Pool owner(s)
    sPoolOwnerVkeys <-
      mapM
        (\(VerificationKeyFile fp) -> do
          StakingVerificationKeyShelley svk <-
            firstExceptT CardanoApiError $ newExceptT $ readStakingVerificationKey fp
          pure svk
        )
        ownerVerFps
    let stakePoolOwners = Set.fromList $ map hashKey sPoolOwnerVkeys

    let registrationCert = shelleyRegisterStakePool
                             (hashKey stakePoolVerKey)
                             (hash vrfVerKey)
                             pldg
                             pCost
                             pMrgn
                             rewardAccount
                             stakePoolOwners
                             relays
                             Nothing

    firstExceptT CardanoApiError . newExceptT $ writeCertificate outfp registrationCert

runStakePoolRetirementCert
  :: VerificationKeyFile
  -> Shelley.EpochNo
  -> OutputFile
  -> ExceptT CliError IO ()
runStakePoolRetirementCert (VerificationKeyFile sPvkeyFp) retireEpoch (OutputFile outfp) = do
    -- Pool verification key
    stakePoolVerKey <- firstExceptT CardanoApiError . newExceptT $ readVerificationKeyStakePool sPvkeyFp

    let retireCert = shelleyRetireStakePool stakePoolVerKey retireEpoch

    firstExceptT CardanoApiError . newExceptT $ writeCertificate outfp retireCert
