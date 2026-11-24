import pathlib, sys, tempfile, unittest, types
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
import numpy as np
import gymnasium as gym
from stable_baselines3 import SAC
from ml.modelos.sac_modelo import exportar, prever
from ml.modelos.modelos_io import guardar, carregar_json
from ml.treino.treinador import _preparar_ficheiro, treinar
from unittest.mock import patch
import torch
torch.set_num_threads(1)

class Simulado(gym.Env):
    observation_space = gym.spaces.Box(np.array([-1,-1,0,0,0,0,0],dtype=np.float32),np.ones(7,dtype=np.float32))
    action_space = gym.spaces.Box(-1.,1.,(2,),dtype=np.float32)
    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        self.steps = 0
        return np.array([0,0,1,1,1,1,1],dtype=np.float32), {}
    def step(self, action):
        self.steps += 1
        return np.array([action[0],action[1],1,1,1,1,1],dtype=np.float32), float(-np.square(action).sum()), False, self.steps>=8, {}

class Tests(unittest.TestCase):
    def test_train_export_resume(self):
        model=SAC('MlpPolicy',Simulado(),policy_kwargs={'net_arch':[64,64]},learning_starts=4,buffer_size=100,batch_size=4,seed=9,device='cpu')
        model.learn(16)
        self.assertGreater(model._n_updates,0)
        data=exportar(model)
        rng=np.random.default_rng(2)
        for _ in range(100):
            obs=rng.uniform(model.observation_space.low,model.observation_space.high).astype(np.float32)
            np.testing.assert_allclose(prever(data,obs),model.predict(obs,deterministic=True)[0],atol=1e-6)
        with tempfile.TemporaryDirectory() as folder:
            name=str(pathlib.Path(folder)/'sac')
            guardar(model, 'sac_mlp', name)
            data_disk=carregar_json(name)
            np.testing.assert_allclose(prever(data_disk,obs),model.predict(obs,deterministic=True)[0],atol=1e-6)
            restored=_preparar_ficheiro(model, 'sac_mlp', name, True)
            self.assertEqual(restored.replay_buffer.size(),model.replay_buffer.size())
            restored.learn(4,reset_num_timesteps=False)
            self.assertEqual(restored.num_timesteps,20)
    def test_training_manager(self):
        def factory(env, name, folder, seed):
            pathlib.Path(folder,'modelos').mkdir(exist_ok=True)
            return SAC('MlpPolicy',env,policy_kwargs={'net_arch':[32,32]},learning_starts=4,buffer_size=100,batch_size=4,seed=seed,device='cpu')
        with tempfile.TemporaryDirectory() as folder, patch('ml.treino.treinador._criar_modelo', side_effect=factory):
            config=dict(modelo='sac_mlp',passos=16,continuar=False,guardar_cada=1,seed=9)
            treinar(Simulado(),config,folder)
            name=str(pathlib.Path(folder)/'ml/pesos/sac_mlp')
            # The production factory normally creates these directories.
            self.assertTrue(pathlib.Path(name+'.json').is_file())
            config.update(passos=4,continuar=True)
            treinar(Simulado(),config,folder)
            restored=SAC.load(name,device='cpu')
            self.assertEqual(restored.num_timesteps,20)
            self.assertGreater(restored._n_updates,0)

    def test_invalid_observation(self):
        with self.assertRaises(ValueError): prever({'observacoes':7},[0]*6)

if __name__=='__main__': unittest.main()
