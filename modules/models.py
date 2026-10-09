import torch
import torch.nn as nn
import torch.nn.functional as F

from .features import INPUT_DIM, SEQUENCE_LENGTH
from .vocabulary import NUM_CLASSES


class DepthwiseConv1D(nn.Module):
    def __init__(self, in_channels, out_channels, kernel_size=3, padding=1):
        super().__init__()
        self.depthwise = nn.Conv1d(
            in_channels,
            in_channels,
            kernel_size=kernel_size,
            padding=padding,
            groups=in_channels,
            bias=False,
        )
        self.pointwise = nn.Conv1d(in_channels, out_channels, kernel_size=1, bias=False)
        self.norm = nn.GroupNorm(4, out_channels)
        self.activation = nn.ReLU()

    def forward(self, inputs):
        return self.activation(self.norm(self.pointwise(self.depthwise(inputs))))


class AttentionPooling(nn.Module):
    def __init__(self, hidden_dim):
        super().__init__()
        self.score = nn.Sequential(
            nn.Linear(hidden_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, 1, bias=False),
        )

    def forward(self, sequence):
        weights = torch.softmax(self.score(sequence).squeeze(-1), dim=1)
        pooled = torch.sum(sequence * weights.unsqueeze(-1), dim=1)
        return pooled, weights


class SignLanguageEncoder(nn.Module):
    def __init__(self, input_dim=INPUT_DIM, hidden_dim=64, num_layers=2, dropout_rate=0.5):
        super().__init__()
        self.conv_block = nn.Sequential(
            DepthwiseConv1D(input_dim, 64),
            DepthwiseConv1D(64, 128),
            DepthwiseConv1D(128, 64),
        )
        self.gru = nn.GRU(
            64,
            hidden_dim,
            num_layers,
            batch_first=True,
            dropout=dropout_rate if num_layers > 1 else 0.0,
        )
        self.attention = AttentionPooling(hidden_dim)
        self.dropout = nn.Dropout(dropout_rate)

    def forward_sequence(self, inputs):
        sequence = self.conv_block(inputs.transpose(1, 2)).transpose(1, 2)
        sequence, _ = self.gru(sequence)
        return sequence

    def forward(self, inputs, return_attention=False):
        sequence = self.forward_sequence(inputs)
        pooled, weights = self.attention(sequence)
        pooled = self.dropout(pooled)
        return (pooled, weights) if return_attention else pooled


class SignLanguageModel(nn.Module):
    # def __init__(self, num_classes=73, input_dim=INPUT_DIM, hidden_dim=64, num_layers=2):
    def __init__(self, num_classes=NUM_CLASSES, input_dim=INPUT_DIM, hidden_dim=64, num_layers=2):
        super().__init__()
        self.config = {
            "num_classes": num_classes,
            "input_dim": input_dim,
            "hidden_dim": hidden_dim,
            "num_layers": num_layers,
        }
        self.encoder = SignLanguageEncoder(input_dim, hidden_dim, num_layers)
        self.classifier = nn.Linear(hidden_dim, num_classes)

    def forward(self, inputs, return_attention=False):
        if return_attention:
            features, weights = self.encoder(inputs, return_attention=True)
            return self.classifier(features), weights
        return self.classifier(self.encoder(inputs))


class MaskedSequenceAutoencoder(nn.Module):
    def __init__(self, encoder, output_dim=INPUT_DIM, output_length=SEQUENCE_LENGTH):
        super().__init__()
        self.encoder = encoder
        self.output_length = output_length
        self.decoder = nn.Linear(encoder.gru.hidden_size, output_dim)

    def forward(self, inputs):
        encoded = self.encoder.forward_sequence(inputs).transpose(1, 2)
        encoded = F.interpolate(encoded, size=self.output_length, mode="linear", align_corners=False)
        return self.decoder(encoded.transpose(1, 2))


class _GradientReversal(torch.autograd.Function):
    @staticmethod
    def forward(ctx, inputs, strength):
        ctx.strength = strength
        return inputs.view_as(inputs)

    @staticmethod
    def backward(ctx, gradients):
        return -ctx.strength * gradients, None


class SignerClassifier(nn.Module):
    def __init__(self, hidden_dim, num_signers):
        super().__init__()
        self.classifier = nn.Linear(hidden_dim, num_signers)

    def forward(self, features, strength=1.0):
        reversed_features = _GradientReversal.apply(features, strength)
        return self.classifier(reversed_features)
